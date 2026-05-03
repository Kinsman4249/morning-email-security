# Alert Logic — How `debsecan-filtered.sh` Works

This doc explains the internal pipeline of `debsecan-filtered.sh`. Read it if you want to understand exactly why a particular CVE did or didn't show up in your morning email — or if you want to modify the filter logic.

> **v1.0 simplification:** The filter was rewritten in v1.0 to use only `debsecan`'s local judgement — no separate Debian Security Tracker JSON API calls. Smaller surface area, easier to audit, fewer moving parts. If you're upgrading from v0.5.x, the bucket criteria are unchanged but the pipeline is leaner.

## High-level flow

```
debsecan (raw output, hundreds of CVEs)
   ↓
Phase 1 — Collect CVE data (one debsecan call per format)
   ↓
Phase 2 — Build unfixed list (all − fixed)
   ↓
Phase 2b — Strip Debian-triaged CVEs from unfixed list
   ↓
Phase 3 — Detect listening packages + source-package expansion
   ↓
Phase 4 — Bucket A and Bucket B filters
   ↓
Phase 5 — Update first-seen / last-seen CSV cache
   ↓
Phase 6 — Send email (or skip if zero results)
```

Each phase logs to stderr with a `[debsecan-filtered]` prefix, so `journalctl -u cron` (or piping the script to a log file) gives you a complete trace.

## Phase 1 — Collect CVE data

Two `debsecan` calls:

- `--only-fixed --format detail` → all patchable CVEs (multi-line per CVE, includes `installed:` / `fixed:` info)
- `--format detail` → all CVEs (patchable + unpatched)

Storing both lets Phase 2 derive the unfixed set without a second network round-trip.

## Phase 2 — Build unfixed list

We need CVEs that are NOT in the fixed set (because Bucket B is "no patch available"). The script:

1. Extracts `CVE PACKAGE` keys from the fixed set into an awk-friendly lookup.
2. Walks the all-CVE set and keeps blocks whose `CVE PACKAGE` is NOT in that lookup.

Result: `ALL_UNFIXED` contains only CVEs with no available patch.

## Phase 2b — Strip Debian-triaged CVEs from unfixed list

`debsecan --format detail` includes triage tags inside the detail block. The filter walks each CVE block and drops any block whose detail lines mention `no-dsa`, `ignored`, `end-of-life`, `not-affected`, or `postponed`.

This strips the noise without needing an external API: Debian's security team has already decided these don't need action, and that decision is reflected in the local `debsecan` output.

The number of stripped CVEs is logged, e.g. `Stripped 47 Debian-triaged CVEs from unfixed list (123 -> 76)`.

## Phase 3 — Detect listening packages + source expansion

This is where the filter focuses on what's actually exposed to the network.

### Step 3a — Initial listening binaries

`ss -tlnp` lists TCP listening sockets with PIDs. For each PID, the filter:

1. Reads `/proc/PID/exe` to get the executable path.
2. Asks `dpkg -S /path/to/exe` which package owns it.

Result: `LISTEN` — a set of binary package names with at least one open listening port.

### Step 3b — Source-package expansion

A binary package is a small slice of its source package's output. `openssh` is the source package; it produces `openssh-server`, `openssh-client`, `openssh-sftp-server`, etc. A CVE in the source affects all of them — but `debsecan` reports per-binary-package, and only one of those binaries may be listening.

The filter solves this by:

1. For each listening binary, look up its source package name (`dpkg-query -W -f '${Source}\n'`).
2. Get all binary packages built from that source (`dpkg-query -W -f '${Package}\t${Source}\n'`, filter by source name).
3. Add every sibling to the `EXPANDED` set.

Without this expansion, you'd miss CVEs filed against `openssh-client` even when `openssh-server` is the listening daemon.

The final expanded set is collected in `LISTEN_PKGS`.

## Phase 4 — Bucket A and Bucket B filters

Both buckets use a block-aware awk pattern, with different match logic.

### Bucket A — Patchable (broad)

Operates on `ALL_FIXED` (patchable CVEs).

Inclusion criteria — if **any** match, include the block:

- Line contains `remotely exploitable`
- Line contains `high urgency` or `critical urgency`
- Package is in the listening-pkg lookup

### Bucket B — Unpatched, network-exposed (tight)

Operates on `ALL_UNFIXED` (unfixed CVEs after the Phase 2b triage strip).

Inclusion criterion — must match:

- Package is in the listening-pkg lookup

### Why the criteria differ

Bucket A has thousands of candidates because Debian patches a lot of CVEs. The broad criteria — remote exploit OR high urgency OR listening — let you see things you should patch even if they're not currently network-exposed (e.g., a high-urgency local-priv-esc bug in a system library).

Bucket B is tighter because the manual mitigation work is much higher-cost. We only surface unpatched CVEs you genuinely have to deal with — i.e., the ones with an open port.

## Phase 5 — First-seen / last-seen cache

`/var/cache/debsecan-filtered/seen-cves.csv` records currently-actionable CVEs:

```csv
cve_id,package,bucket,first_seen,last_seen
CVE-2024-12345,openssh-server,A,2026-04-15,2026-05-03
CVE-2024-67890,nginx,B,2026-04-22,2026-05-03
```

The CSV is rewritten fresh on each run with the current actionable set; cleared CVEs naturally drop out.

> **Changed in v1.0:** v0.5.x maintained a separate `triage-skip.csv` file. v1.0 removed that file because triage stripping is now an in-script awk pass against `debsecan` output rather than a pre-computed lookup.

## Phase 6 — Send email

### When zero results

If both buckets are empty:

- In normal mode (cron): no email is sent. Silence = clean.
- In `--test` mode: an email is sent anyway so you can verify the script ran correctly.

### When there are results

Subject line format:

```
[debsecan] {COUNT} actionable CVE(s) - {hostname}
```

Body structure:

1. Counts: `Bucket A (patchable): N` and `Bucket B (unpatched, listening): N`
2. Bucket A details (if any).
3. Bucket B details (if any).

## Cache schema reference

### `/var/cache/debsecan-filtered/seen-cves.csv`

One row per currently-actionable CVE+package combo.

```csv
cve_id,package,bucket,first_seen,last_seen
CVE-2024-12345,openssh-server,A,2026-04-15,2026-05-03
```

Bucket values: `A` (patchable) or `B` (unpatched, network-exposed).

## Modifying the logic

The filter is plain Bash + awk. Common modifications:

- **Tighten Bucket A** to "listening port only" (remove the urgency/remote criteria) — edit Phase 4's `filter_bucket_a` awk block and delete the `remotely exploitable` and `high urgency|critical urgency` lines.
- **Add medium urgency** to Bucket A — add `if (line ~ /medium urgency/) keep = 1` next to the existing urgency line.
- **Skip a known noisy CVE** — pre-grep `ALL_FIXED` and `ALL_UNFIXED` to remove specific CVE IDs before bucket filtering.
- **Change the email format** — Phase 6 builds the body in a single `{ ... }` group piped to `msmtp`. Easy to refactor.

When in doubt, run with `--test` after every edit to see the new output without waiting for cron.
