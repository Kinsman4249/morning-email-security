# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned

- Optional systemd timer alternative to cron-based scheduling
- Multi-host config-bundle support (deploy to a fleet via one config file)
- Optional Slack/webhook delivery in addition to email
- A pre-1.0 → 1.0 hardening pass: full ShellCheck-clean, integration tests in containers, signed releases
- Lock file to prevent overlapping cron runs on slow networks

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

### Known limitations

- Single-host install only — no fleet/multi-host orchestration in this release.
- No locking on the filter script — extremely slow networks could in theory overlap two cron runs.
- Email delivery only — no Slack, webhook, or other delivery backends yet.
- Tested on Debian 11/12 and Ubuntu 22.04/24.04. Other Debian-derivatives may work but are not exercised in CI.

[Unreleased]: https://github.com/Kinsman4249/morning-email-security/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Kinsman4249/morning-email-security/releases/tag/v0.5.0
