# Alert Logic — How `debsecan-filtered` Works

This doc explains the internal pipeline of `debsecan-filtered`. Read it if you want to understand exactly why a particular CVE did or didn't show up in your morning email — or if you want to modify the filter logic.

## High-level flow

```
debsecan (raw output, hundreds of CVEs)
   ↓
Phase 1 — Build Debian-triage skip list
   ↓
Phase 2 — Fetch detail-format CVE data (patchable + all)
   ↓
Phase 3 — Strip triaged CVEs from detail data
   ↓
Phase 4 — Compute "unfixed" set (all − fixed)
   ↓
Phase 5 — Build listening-package list (with source expansion)
   ↓
Phase 6 — Apply Bucket A and Bucket B filters, dedup
   ↓
Phase 7 — Update first-seen / last-seen CSV cache
   ↓
Phase 8 — Build and send email (or skip if zero results)
   ↓
Phase 9 — Clean up temp files
```

Each phase logs to stderr with a `[debsecan-filtered]` prefix, so `journalctl -u cron` (or piping the script to a log file) gives you a complete trace.

## Phase 1 — Triage skip list

`debsecan` has two output formats: `default` (compact, includes triage flags) and `detail` (verbose, no flags). Phase 1 runs the default format to extract CVEs that the Debian security team has classified as:

- `(no-dsa)` — won't get a Debian Security Advisory (low severity, end-user fix only, etc.)
- `(ignored)` — won't be fixed
- `(end-of-life)` — package is past EoL
- `(not-affected)` — Debian's package isn't actually vulnerable
- `(postponed)` — fix planned but not coming soon

These are stored as `cve,package,flag` rows in `/var/cache/debsecan-filtered/triage-skip.csv`, then converted to a fast-lookup file (`.skip-lookup`) keyed on `CVE PACKAGE`.

The script accepts both `(parens)` and `<angle-bracket>` flag styles to handle slight differences across `debsecan` versions.

## Phase 2 — Fetch detail-format CVE data

Two `debsecan` calls:

- `--only-fixed --format detail` → all patchable CVEs (multi-line per CVE, includes `installed:` / `fixed:` info)
- `--format detail` → all CVEs (patchable + unpatched)

Storing both lets Phase 4 derive the unfixed set without a second network round-trip.

## Phase 3 — Strip triaged CVEs from detail data

This is **block-aware** awk: `debsecan --format detail` produces multi-line records that look like:

```
CVE-2024-12345 openssh-server  remote, high urgency
   installed: 1:9.2p1-2+deb12u9
   fixed:     1:9.2p1-2+deb12u10
```

The filter walks the lines: a `CVE-` line starts a new block. If `CVE PACKAGE` is in the skip lookup, suppress the entire block until the next `CVE-` line. This way, indented detail lines don't survive when their parent CVE was triaged.

Counts before and after are logged so you can see how much noise the pre-filter removed.

## Phase 4 — Compute unfixed set

We need CVEs that are NOT in the fixed set (because Bucket B is "no patch available"). The script:

1. Extracts `CVE PACKAGE` keys from the fixed set into `.fixed-keys`.
2. Walks the all-CVE set with the same block-aware awk pattern, suppressing blocks whose `CVE PACKAGE` IS in `.fixed-keys`.

Result: `ALL_UNFIXED` contains only CVEs with no available patch.

## Phase 5 — Listening-package list

This is where the filter focuses on what's actually exposed to the network.

### Step 5a — Initial listening binaries

`ss -tlnp` lists TCP listening sockets with PIDs. For each PID, the filter:

1. Reads `/proc/PID/exe` to get the executable path.
2. Asks `dpkg -S /path/to/exe` which package owns it.

Result: `LISTEN_MAP` — a set of binary package names with at least one open listening port.

### Step 5b — Source-package expansion

A binary package is a small slice of its source package's output. `openssh` is the source package; it produces `openssh-server`, `openssh-client`, `openssh-sftp-server`, etc. A CVE in the source affects all of them — but `debsecan` reports per-binary-package, and only one of those binaries may be listening.

The filter solves this by:

1. For each listening binary, look up its source package name (`dpkg-query -W -f '${Source}\n'`).
2. Get all binary packages built from that source (`dpkg-query -W -f '${Package}\t${Source}\n'`, filter by source name).
3. Add every sibling to `LISTEN_MAP`.

Without this expansion, you'd miss CVEs filed against `openssh-client` even when `openssh-server` is the listening daemon.

The expansion is logged: `openssh-server -> source: openssh -> adding: openssh-client, openssh-sftp-server`.

### Step 5c — Build awk-friendly lookup

The expanded list is joined with `|` for use in awk regex matching:

```
openssh-server|openssh-client|openssh-sftp-server|nginx|...
```

## Phase 6 — Bucket A and Bucket B filters

Both buckets use the same block-aware awk pattern as Phase 3, with different match logic.

### Bucket A — Patchable (broad)

Operates on `ALL_FIXED` (patchable CVEs after triage strip).

Inclusion criteria — if **any** match, include the block:

- Line contains `remotely exploitable`
- Line contains `high urgency` or `critical urgency`
- Package is in the listening-pkg lookup

Then dedup by `CVE PACKAGE` — if the same combo appears twice, only the first is kept.

### Bucket B — Unpatched, network-exposed (tight)

Operates on `ALL_UNFIXED` (unfixed CVEs after triage strip).

Inclusion criterion — must match:

- Package is in the listening-pkg lookup

Then dedup the same way.

### Why the criteria differ

Bucket A has thousands of candidates because Debian patches a lot of CVEs. The broad criteria — remote exploit OR high urgency OR listening — let you see things you should patch even if they're not currently network-exposed (e.g., a high-urgency local-priv-esc bug in a system library).

Bucket B is tighter because the manual mitigation work is much higher-cost. We only surface unpatched CVEs you genuinely have to deal with — i.e., the ones with an open port.

## Phase 7 — First-seen / last-seen cache

`/var/cache/debsecan-filtered/seen-cves.csv` is the long-running record:

```csv
cve_id,package,bucket,first_seen,last_seen
CVE-2024-12345,openssh-server,A,2026-04-15,2026-05-03
CVE-2024-67890,nginx,B,2026-04-22,2026-05-03
```

On each run, the filter:

1. Loads the existing CSV into memory.
2. Walks Bucket A and Bucket B results, looking each up in the old cache.
3. If found, preserves the original `first_seen` and updates `last_seen` to today.
4. If new, sets both to today and increments a "new since last run" counter.
5. Writes the new CSV (overwriting the old one — only currently-actionable CVEs are tracked, so cleared CVEs naturally drop out).

The "new since last run" count appears in every email body so you know how the situation changed overnight.

## Phase 8 — Build and send email

### When zero results

If both buckets are empty:

- In normal mode (cron): no email is sent. Silence = clean.
- In `--test` mode: an explainer email is sent showing the totals at each stage of the pipeline (so you can verify the script ran correctly).

### When there are results

Subject line format:

```
[debsecan] {COUNT} actionable CVE(s) [{A_COUNT} patchable, {B_COUNT} unpatched] - {hostname} - {date}
```

In `--test` mode the prefix becomes `[debsecan] TEST`.

Body structure:

1. Headline counts and "new since last run".
2. Bucket A criteria recap.
3. Bucket B criteria recap.
4. Listening packages (expanded).
5. Total counts at each pipeline stage.
6. Bucket A details (if any).
7. Bucket B details (if any) — followed by deduplicated `https://security-tracker.debian.org/tracker/CVE-...` links.
8. Footer with cache location and reference URLs.

## Phase 9 — Cleanup

Temp files (`.skip-lookup`, `.fixed-keys`) are removed. Persistent cache files (`triage-skip.csv`, `seen-cves.csv`) stay.

## Cache schema reference

### `/var/cache/debsecan-filtered/triage-skip.csv`

Built fresh on every run. Maps Debian-triaged CVEs to their flags.

```csv
cve_id,package,flag
CVE-2024-11111,libfoo1,no-dsa
CVE-2024-22222,libbar0,end-of-life
```

### `/var/cache/debsecan-filtered/seen-cves.csv`

Long-running. One row per currently-actionable CVE+package combo.

```csv
cve_id,package,bucket,first_seen,last_seen
CVE-2024-12345,openssh-server,A,2026-04-15,2026-05-03
```

Bucket values: `A` (patchable) or `B` (unpatched, network-exposed).

## Modifying the logic

The filter is plain Bash + awk. Common modifications:

- **Tighten Bucket A** to "listening port only" (remove the urgency/remote criteria) — edit Phase 6's Bucket A awk block.
- **Add medium urgency** to Bucket A — add `if (line ~ /medium urgency/) printing = 1` next to the existing urgency line.
- **Skip a known noisy CVE** — add it to a custom skip file and load it the same way Phase 1 loads `triage-skip.csv`.
- **Change the email format** — Phase 8 builds the body in a single `BODY+=` chain. Easy to refactor.

When in doubt, run with `--test` after every edit to see the new output without waiting for cron.
