# morning-email-security

> Daily email alerts for actionable Debian CVEs and package updates. A drop-in cron-driven installer that wires up `debsecan` + `apticron` + `msmtp` on Debian/Ubuntu hosts and emails only what you need to act on.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-green.svg)](setup-cve-alerts.sh)
[![Platform: Debian | Ubuntu](https://img.shields.io/badge/platform-debian%20%7C%20ubuntu-orange.svg)]()
[![Status: Pre-1.0](https://img.shields.io/badge/status-pre--1.0-yellow.svg)](CHANGELOG.md)

---

## Why this exists

`debsecan` will dutifully report **every** CVE that touches your installed packages. On a typical Debian server that means hundreds of advisories, most of which the Debian security team has already triaged as `(no-dsa)`, `(ignored)`, `(end-of-life)`, `(not-affected)`, or `(postponed)`. Reading those every morning trains you to ignore the email.

`morning-email-security` filters that firehose into two short, decision-ready lists:

- **Bucket A — Patchable.** A fix is in the Debian repos, AND the CVE is remotely exploitable, OR high/critical urgency, OR the affected package has an open listening port on this host. *Action: `apt-get upgrade`.*
- **Bucket B — Unpatched, network-exposed.** No fix in Debian yet, AND the affected package has an open listening port. *Action: read the linked Debian tracker pages and apply manual mitigations.*

If neither bucket has results, **no email is sent** — silence means your morning is clean.

---

## Quickstart

On a Debian or Ubuntu host with root access:

```bash
git clone https://github.com/Kinsman4249/morning-email-security.git
cd morning-email-security
sudo bash setup-cve-alerts.sh
```

You'll be prompted for SMTP credentials (defaults are pre-filled for [SMTP2GO](https://www.smtp2go.com/)). Two emails arrive when setup finishes:

1. **Setup summary** — host info, component status, schedule, configuration.
2. **CVE test run** — the same filtered alert you'll receive every morning, or a "no actionable CVEs" explainer if everything's clean.

That's it. The daily cron job runs at 07:00 and emails only when there's something to act on.

---

## Components

| Component | Role |
| --- | --- |
| **`setup-cve-alerts.sh`** | Interactive installer. Configures `msmtp`, `apticron`, `debsecan`; deploys the filter; sets up cron; sends two test emails. |
| **`debsecan-filtered`** | Daily filter that turns raw `debsecan` output into actionable Bucket A / Bucket B lists. Installed to `/usr/local/bin/`. |
| **`uninstall.sh`** | Companion uninstaller that reverses everything `setup-cve-alerts.sh` did. |
| **`msmtp`** | SMTP relay. Replaces the default mail handler with one that talks to your SMTP provider. |
| **`apticron`** | Daily check for available package updates. Emails when updates are available. |
| **`debsecan`** | Debian Security Analyzer. Scans installed packages against the Debian Security Tracker. |

---

## Prerequisites

- **OS:** Debian 11/12, Ubuntu 22.04/24.04, or any close derivative.
- **Access:** root or sudo.
- **SMTP relay:** account with any SMTP provider (SMTP2GO, Mailgun, AWS SES, Postmark, SendGrid, Gmail App Password, etc.). You'll need:
  - SMTP host + port
  - Username + password
  - A verified sender (`From`) address
  - A destination (`To`) address for alerts

See [`docs/SMTP_PROVIDERS.md`](docs/SMTP_PROVIDERS.md) for a quick-reference matrix of common providers.

---

## Installation

### Option 1 — Interactive

```bash
sudo bash setup-cve-alerts.sh
```

Prompts you for each value with defaults pre-filled for SMTP2GO. Press Enter to accept defaults.

### Option 2 — Pre-filled (CI / Ansible / unattended)

```bash
sudo FROM_EMAIL="alerts@yourdomain.com" \
     TO_EMAIL="admin@yourdomain.com" \
     SMTP_HOST="mail.smtp2go.com" \
     SMTP_PORT="2525" \
     SMTP_USER="your-smtp-user" \
     SMTP_PASS="your-smtp-password" \
     bash setup-cve-alerts.sh
```

Any variable you export before invoking the script skips its prompt. You'll still get the final `Proceed? [Y/n]` confirmation — pipe `yes` or pre-answer if you want fully unattended.

### What the installer does

1. `apt-get install -y msmtp msmtp-mta mailutils apticron debsecan ca-certificates`
2. Writes `/etc/msmtprc` (chmod 600) with your SMTP relay config.
3. Sets `msmtp` as the system's default sendmail.
4. Writes `/etc/apticron/apticron.conf` with your alert addresses.
5. Wipes the filter cache (`/var/cache/debsecan-filtered`) for a fresh start.
6. Deploys `debsecan-filtered` to `/usr/local/bin/` with email addresses baked in.
7. Writes `/etc/cron.d/debsecan-report` (runs daily at 07:00).
8. Runs component status checks.
9. Emails (1) a setup summary and (2) a test filter run.
10. Removes the installer files from your upload directory.

> **Re-running:** Safe to re-run any time. Every config file is written with truncate-and-replace; package installs are idempotent. To re-run, **re-upload the source files first** — the installer cleans them up at the end.

---

## Alert Criteria (Bucket A vs. Bucket B)

The full filter pipeline is detailed in [`docs/ALERT_LOGIC.md`](docs/ALERT_LOGIC.md). At a glance:

### Pre-filter — Debian-triaged CVEs are stripped

CVEs that Debian's security team has already classified as `(no-dsa)`, `(ignored)`, `(end-of-life)`, `(not-affected)`, or `(postponed)` are removed before any further evaluation. They're noise, not signal.

### Bucket A — Patchable

A CVE lands here when **all** of:

- Fix is available in the Debian repos for your suite, AND
- One or more of:
  - Remotely exploitable, OR
  - High or critical urgency, OR
  - Affected package has an open listening port on this host (with source-package expansion — see below).

**Action:** `sudo apt-get upgrade`.

### Bucket B — Unpatched, network-exposed

A CVE lands here when **all** of:

- No fix is available in the Debian repos for your suite, AND
- Affected package has an open listening port on this host.

**Action:** Open the per-CVE tracker links in the email and apply manual mitigations (config changes, access restrictions, WAF rules, disabling unused features). Bucket B emails always include direct links to `https://security-tracker.debian.org/tracker/CVE-XXXX-XXXXX` for each affected CVE.

### Source-package expansion

Listening binary packages get expanded to **all sibling binaries from the same source package**. Example: if `openssh-server` has an open port, the filter also evaluates CVEs against `openssh-client`, `openssh-sftp-server`, etc. — because they share the source tree, a CVE in one often affects the others.

### "First seen" tracking

`/var/cache/debsecan-filtered/seen-cves.csv` records the first and most recent date each CVE+package combination appeared in an alert. The filter uses this to count "new since last run" in every email.

---

## Schedule

Daily at **07:00**, defined in `/etc/cron.d/debsecan-report`. Edit that file to change the time:

```cron
# Example: 06:00 instead of 07:00
0 6 * * * root /usr/local/bin/debsecan-filtered
```

`apticron` runs on its own daily timer (`/etc/cron.daily/apticron`) and emails when package updates are available.

See [`examples/cron-custom.conf`](examples/cron-custom.conf) for alternate schedule snippets (twice-daily, weekday-only, business-hours, etc.).

---

## Testing

Trigger an immediate filter run that emails regardless of whether actionable CVEs exist:

```bash
sudo /usr/local/bin/debsecan-filtered --test
```

Useful for verifying email delivery without waiting for the morning cron.

Wipe the cache to force a fresh start:

```bash
sudo /usr/local/bin/debsecan-filtered --flush-cache
```

---

## File Locations

| Path | Purpose |
| --- | --- |
| `/etc/msmtprc` | SMTP relay config (chmod 600, root only — contains password) |
| `/etc/apticron/apticron.conf` | apticron notification settings |
| `/etc/cron.d/debsecan-report` | Daily filter cron entry |
| `/usr/local/bin/debsecan-filtered` | The filter script (deployed, not edited in place) |
| `/var/cache/debsecan-filtered/` | Cache directory |
| `/var/cache/debsecan-filtered/seen-cves.csv` | First-seen / last-seen tracking |
| `/var/cache/debsecan-filtered/triage-skip.csv` | Debian-triaged CVE skip list |
| `/var/log/msmtp.log` | SMTP send log |

---

## Troubleshooting

Quick checks:

```bash
# SMTP not delivering?
sudo cat /var/log/msmtp.log
sudo msmtp --pretend you@example.com < /dev/null

# debsecan errors?
sudo debsecan --suite "$(. /etc/os-release && echo $VERSION_CODENAME)" --format report | head

# Filter run, manually
sudo /usr/local/bin/debsecan-filtered --test
```

For deeper diagnostics see [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## Uninstallation

```bash
sudo bash uninstall.sh
```

Or follow the step-by-step in [`docs/SETUP_GUIDE.md`](docs/SETUP_GUIDE.md#uninstallation) if you want to remove specific components only.

---

## Documentation

- **[`docs/SETUP_GUIDE.md`](docs/SETUP_GUIDE.md)** — long-form setup guide (Markdown port of the original Word doc)
- **[`docs/SETUP_GUIDE.docx`](docs/SETUP_GUIDE.docx)** — original Word document
- **[`docs/ALERT_LOGIC.md`](docs/ALERT_LOGIC.md)** — deep-dive on the 9-phase filter pipeline
- **[`docs/SMTP_PROVIDERS.md`](docs/SMTP_PROVIDERS.md)** — SMTP provider quick-reference matrix
- **[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)** — extended troubleshooting cookbook

---

## Status

This project is **pre-1.0** (currently `v0.5.0`). Core functionality is stable and in production use; some polish and convenience features are still in flight. See [`CHANGELOG.md`](CHANGELOG.md) for what's done and [issues](https://github.com/Kinsman4249/morning-email-security/issues) for what's planned.

---

## Contributing

Contributions welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for community expectations. Security issues: please follow [`SECURITY.md`](SECURITY.md) — don't file them publicly.

---

## License

Apache License 2.0. See [`LICENSE`](LICENSE).

Copyright © 2026 Ethan Antonio.
