# debsecan-filtered.sh

Actionable CVE alerting for Debian servers — powered by `debsecan`, filtered to cut the noise.

## What It Does

Most Debian hosts carry dozens of CVEs that are low-risk or already triaged as *no-dsa* by the Debian Security Team.  
**debsecan-filtered.sh** trims that list down to two actionable buckets and emails you only when something needs attention.

| Bucket | Criteria |
|--------|----------|
| **A — Patchable** | Fix available in Debian repos **AND** at least one of: remotely exploitable, high/critical urgency, or package has an open listening port |
| **B — Unpatched (network-exposed)** | No fix available **AND** package has an open listening port (includes source-package expansion). CVEs triaged by Debian as `no-dsa`, `ignored`, `end-of-life`, `not-affected`, or `postponed` are **excluded**. |

An email is sent only when **either** bucket has results.

## Design Principles

- **Quiet by default** — no email when there's nothing to act on
- **Deterministic** — same inputs → same output
- **Cron-safe** — runs unattended, exits cleanly
- **No external network calls** — trusts Debian's local `debsecan` judgement only
- **Actionable only** — filters out noise so every alert deserves attention

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Debian-based system | Tested on Debian 11/12 |
| Root access | Setup installs packages and writes to `/etc` |
| Working SMTP relay | Default config targets SMTP2GO; any relay works |

The setup script installs all required packages automatically:  
`msmtp` · `msmtp-mta` · `mailutils` · `apticron` · `debsecan` · `ca-certificates` · `curl`

## Installation

```bash
git clone https://github.com/Kinsman4249/morning-email-security.git
cd morning-email-security
sudo bash setup-cve-alerts.sh
```

The installer will prompt for:

| Prompt | Default |
|--------|---------|
| From address | *(none — required)* |
| To address | *(none — required)* |
| SMTP host | `mail.smtp2go.com` |
| SMTP port | `2525` |
| SMTP username | *(none — required)* |
| SMTP password | *(none — required, hidden)* |

You can prefill any value via environment variables to skip its prompt:

```bash
sudo FROM_EMAIL="alerts@example.com" TO_EMAIL="admin@example.com" \
     SMTP_USER="myuser" SMTP_PASS="mypass" \
     bash setup-cve-alerts.sh
```

On completion the installer sends **two emails**: a setup summary and a filtered CVE test run.

## Usage Flags

Run the filter script manually at any time:

```bash
sudo /usr/local/bin/debsecan-filtered.sh          # normal run (email only if actionable)
sudo /usr/local/bin/debsecan-filtered.sh --test    # always send email (even if 0 CVEs)
sudo /usr/local/bin/debsecan-filtered.sh --flush-cache   # wipe cache and exit
```

## File Locations

| Path | Purpose |
|------|---------|
| `/usr/local/bin/debsecan-filtered.sh` | Filter script |
| `/etc/cron.d/debsecan-report` | Cron job (daily 07:00) |
| `/var/cache/debsecan-filtered/` | Cache directory |
| `/var/cache/debsecan-filtered/seen-cves.csv` | Tracks `first_seen` / `last_seen` per CVE |
| `/etc/msmtprc` | SMTP relay config (chmod 600) |
| `/etc/apticron/apticron.conf` | Apticron config |

## Schedule

| Component | Frequency | Trigger |
|-----------|-----------|---------|
| **apticron** | Daily | `/etc/cron.daily/apticron` — emails when package updates are available |
| **debsecan-filtered.sh** | Daily at 07:00 | `/etc/cron.d/debsecan-report` — emails when actionable CVEs are found |

## Uninstallation

```bash
sudo bash uninstall.sh
```

The uninstall script removes the filter script, cron job, and cache, then interactively asks whether to remove configs and packages.

## License

[Apache-2.0](LICENSE)
