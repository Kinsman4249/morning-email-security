# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Optional systemd timer alternative to cron-based scheduling
- Multi-host config-bundle support (deploy to a fleet via one config file)
- Optional Slack/webhook delivery in addition to email
- Lock file to prevent overlapping cron runs on slow networks

## [1.0.0] - 2026-05-03

First stable release. The filter script has been simplified, renamed for clarity, and the install/uninstall flow tightened up.

### Changed (breaking)

- **Filename rename:** `debsecan-filtered` → `debsecan-filtered.sh`. The deployed binary at `/usr/local/bin/debsecan-filtered.sh` and the source script in this repo both use the `.sh` extension. The cron entry `/etc/cron.d/debsecan-report` references the new path. Re-running `setup-cve-alerts.sh` cleanly handles the transition.
- **Filter pipeline simplified.** The 9-phase pipeline collapsed to 6 phases. CVE triage stripping is now a single in-script awk pass driven by `debsecan` output (`no-dsa`, `ignored`, `end-of-life`, `not-affected`, `postponed`). Functionally equivalent for the common case, easier to read, fewer moving parts.
- **No external network calls from the filter.** The script trusts Debian's local `debsecan` output and `debsecan`'s own data fetch — no separate Debian Security Tracker JSON API calls. Smaller attack surface, simpler caching.
- **Cache schema:** the filter now maintains only `seen-cves.csv` (first/last seen per CVE+package). The previous `triage-skip.csv` is no longer written.

### Added

- `curl` is now part of the installer's apt install list (in case any downstream user wants to fetch additional content).
- `uninstall.sh` v1.0 — REMOVED/SKIPPED summary at the end of the run, single-pass interactive flow, root check up front.

### Fixed

- Minor wording fixes in the setup-summary email body.

### Migration notes (from v0.5.x)

To upgrade an existing install:

```bash
git pull
sudo bash setup-cve-alerts.sh
```

The installer will overwrite the old `/usr/local/bin/debsecan-filtered` (no extension) with the new `/usr/local/bin/debsecan-filtered.sh`, update the cron entry, and re-run the test. The old binary at `/usr/local/bin/debsecan-filtered` is NOT auto-deleted by `setup-cve-alerts.sh`. To clean it up:

```bash
sudo rm -f /usr/local/bin/debsecan-filtered
```

Or run the new `uninstall.sh` and then re-install fresh.

## [0.5.0] - 2026-05-03

Initial public release. Mid-development — core stack is stable and in production use; some convenience features and hardening are still planned for 1.0.

### Added

- `setup-cve-alerts.sh` — interactive installer that wires up `msmtp`, `apticron`, and `debsecan` end-to-end, with SMTP2GO defaults pre-filled and full prefill-via-env-vars support for unattended installs.
- `debsecan-filtered` — daily filter that turns raw `debsecan` output into actionable Bucket A (patchable) and Bucket B (unpatched, network-exposed) alerts. Includes:
  - Pre-filter: strip CVEs that Debian has triaged as `(no-dsa)`, `(ignored)`, `(end-of-life)`, `(not-affected)`, or `(postponed)`.
  - Source-package expansion: listening binaries are expanded to all sibling binaries from the same source package.
  - First-seen / last-seen tracking via `/var/cache/debsecan-filtered/seen-cves.csv`.
  - `--test` flag (always email, even with zero results) and `--flush-cache` flag.
  - Per-CVE Debian Security Tracker links in Bucket B alerts.
- `uninstall.sh` — companion uninstaller that reverses every change made by the installer.
- Documentation set:
  - `README.md` — canonical install + usage doc.
  - `docs/SETUP_GUIDE.md` — long-form setup guide.
  - `docs/ALERT_LOGIC.md` — deep-dive on the 9-phase filter pipeline.
  - `docs/SMTP_PROVIDERS.md` — SMTP provider quick-reference matrix.
  - `docs/TROUBLESHOOTING.md` — extended troubleshooting cookbook.
- `examples/cron-custom.conf` — alternate schedule snippets.
- Community files: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue templates, PR template.
- CI: `shellcheck.yml` workflow lints all shell scripts on PR.
- CI: `release.yml` workflow auto-creates GitHub Releases with downloadable assets when a `v*` tag is pushed.

### Known limitations (resolved in v1.0)

- ~~Single-host install only~~ — still single-host in v1.0.
- ~~No locking on the filter script~~ — still no lock file in v1.0.
- ~~Email delivery only~~ — still email-only in v1.0.

[Unreleased]: https://github.com/Kinsman4249/morning-email-security/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Kinsman4249/morning-email-security/releases/tag/v1.0.0
[0.5.0]: https://github.com/Kinsman4249/morning-email-security/releases/tag/v0.5.0
