# CVE & Package Update Alert Setup Guide

> Long-form setup guide for **morning-email-security**.

## Overview

This guide walks through installing and configuring an automated CVE (Common Vulnerabilities and Exposures) and package update alerting stack for Debian-based Linux servers. Once configured, the system sends daily email alerts when actionable security vulnerabilities or package updates are detected.

## Components

| Component | Purpose |
| --- | --- |
| `msmtp` | Lightweight SMTP relay client. Replaces the system default mail handler. |
| `apticron` | Daily check for available `apt` package updates. Emails when updates are pending. |
| `debsecan` | Debian Security Analyzer. Scans installed packages against the Debian Security Tracker. |
| `debsecan-filtered.sh` | The custom filter (this project) that turns raw `debsecan` output into actionable alerts. |
| `setup-cve-alerts.sh` | The interactive installer (this project). Wires all of the above together. |

## Prerequisites

- A Debian-based Linux server (Debian 11/12, Ubuntu 22.04/24.04, or close derivative).
- Root or sudo access.
- An SMTP relay account. The default configuration uses [SMTP2GO](https://www.smtp2go.com/), but any provider works. See [`SMTP_PROVIDERS.md`](SMTP_PROVIDERS.md).
- An SMTP username and password for the relay.
- A verified sender (`From`) address with your provider.
- A destination (`To`) address for receiving alerts.

## Files Required

Two files are needed, placed in the same directory:

- `setup-cve-alerts.sh` — the installer
- `debsecan-filtered.sh` — the filter, deployed by the installer

Both live at the root of this repository, so a `git clone` puts them in the right place.

## Installation Steps

### Step 1: Get the files onto the target server

```bash
# Option A: clone the repo
git clone https://github.com/Kinsman4249/morning-email-security.git
cd morning-email-security

# Option B: scp the two files
scp setup-cve-alerts.sh debsecan-filtered.sh user@server:/root/
ssh user@server
cd /root
```

### Step 2: Set execute permissions

```bash
chmod +x setup-cve-alerts.sh
```

> The installer sets permissions on `debsecan-filtered.sh` automatically when it deploys it to `/usr/local/bin/`.

### Step 3: Run the installer

```bash
sudo bash setup-cve-alerts.sh
```

The installer prompts for the following values. Press Enter to accept the default shown in brackets, or type a new value.

| Prompt | Default | Description |
| --- | --- | --- |
| `From address` | *(none)* | The verified sender address with your SMTP provider. |
| `To address` | *(none)* | Where alerts should be sent. |
| `SMTP host` | `mail.smtp2go.com` | SMTP server hostname. |
| `SMTP port` | `2525` | SMTP server port. |
| `SMTP username` | *(none)* | Username for authenticating with the relay. |
| `SMTP password` | *(none)* | Password for authenticating with the relay. *Hidden during input.* |

### Step 4: (Optional) Prefill values for unattended installs

You can skip the interactive prompts by exporting variables before running the script:

```bash
sudo FROM_EMAIL="alerts@yourdomain.com" \
     TO_EMAIL="admin@yourdomain.com" \
     SMTP_HOST="mail.smtp2go.com" \
     SMTP_PORT="2525" \
     SMTP_USER="your-smtp-user" \
     SMTP_PASS="your-smtp-password" \
     bash setup-cve-alerts.sh
```

Any combination works — prefill some, leave others to prompt.

### Step 5: Confirm configuration

After entering all values, the installer displays a summary and asks for confirmation:

```text
==> Configuration:
    From:      alerts@yourdomain.com
    To:        admin@yourdomain.com
    SMTP host: mail.smtp2go.com:2525
    SMTP user: your-smtp-user
    Password:  [hidden]

==> Proceed? [Y/n]:
```

Press Enter or type `Y` to proceed.

### Step 6: Watch the installer run

The installer performs the following automatically:

1. Installs required packages (`msmtp msmtp-mta mailutils apticron debsecan ca-certificates`).
2. Writes `/etc/msmtprc` with SMTP relay configuration (`chmod 600`, root-only).
3. Sets `msmtp` as the system default mail handler.
4. Writes `/etc/apticron/apticron.conf` with the configured email addresses.
5. Wipes the filter cache (`/var/cache/debsecan-filtered/`) for a clean start.
6. Deploys `debsecan-filtered.sh` to `/usr/local/bin/` with sender/recipient baked in.
7. Creates `/etc/cron.d/debsecan-report` for the daily CVE scan (07:00 daily).
8. Runs component status checks.
9. Sends two test emails:
   - **Email 1: Setup summary** — host info, component status, configuration, and CVE totals.
   - **Email 2: Filtered CVE test run** — the same alert you'll receive every morning, or a "no actionable CVEs" explainer if everything's clean.
10. Removes the installer files from your upload directory (final cleanup).

### Step 7: Verify emails

Check the configured inbox for the two setup emails. If they don't arrive:

- Check the SMTP log: `sudo cat /var/log/msmtp.log`
- Verify SMTP credentials in `/etc/msmtprc` (root-only)
- Ensure the sender address is verified with your SMTP provider
- See [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) for detailed diagnostics

## Alert Criteria

`debsecan-filtered.sh` evaluates all CVEs reported by `debsecan` and classifies actionable ones into two buckets.

### Bucket A — Patchable

CVEs that have a fixed version available in the Debian repositories **and** meet at least one of:

- Remotely exploitable
- High or critical urgency
- Affected package has an open listening port on the host

**Action:** Update the affected package(s) — `sudo apt-get upgrade`.

### Bucket B — Unpatched, network-exposed

CVEs that have **no fix available** in Debian repos, but the affected package has an open listening port on the host.

**Action:** Review the per-CVE Debian Security Tracker links included in the email. Apply manual mitigations (configuration changes, access restrictions, WAF rules, disabling unused features, etc.).

An email is sent if either bucket contains results. If both are empty, no email is sent.

For the full filter pipeline, see [`ALERT_LOGIC.md`](ALERT_LOGIC.md).

## Email Types

| Email | When | Trigger |
| --- | --- | --- |
| **Setup summary** | Once, at install time | Run of `setup-cve-alerts.sh` |
| **Setup test (filtered CVEs)** | Once, at install time | Last step of `setup-cve-alerts.sh` |
| **Daily filtered CVE alert** | Daily at 07:00 | `/etc/cron.d/debsecan-report` cron entry, only sent if Bucket A or B has results |
| **apticron package update** | Daily | `/etc/cron.daily/apticron`, only sent if updates are available |

## Schedule

The default schedule is daily at 07:00 server time. To change it, edit `/etc/cron.d/debsecan-report`:

```cron
# Run at 06:00 instead of 07:00
0 6 * * * root /usr/local/bin/debsecan-filtered.sh

# Twice daily (07:00 and 17:00)
0 7,17 * * * root /usr/local/bin/debsecan-filtered.sh

# Weekdays only at 08:00
0 8 * * 1-5 root /usr/local/bin/debsecan-filtered.sh
```

See [`../examples/cron-custom.conf`](../examples/cron-custom.conf) for more snippets.

## Testing

Trigger a filter run that always emails (even with zero results):

```bash
sudo /usr/local/bin/debsecan-filtered.sh --test
```

Wipe the cache to force fresh CVE-state on the next run:

```bash
sudo /usr/local/bin/debsecan-filtered.sh --flush-cache
```

## File Locations

| Path | Purpose |
| --- | --- |
| `/etc/msmtprc` | SMTP relay configuration (chmod 600, root only — contains password) |
| `/etc/apticron/apticron.conf` | apticron notification settings |
| `/etc/cron.d/debsecan-report` | Daily debsecan-filtered.sh cron entry |
| `/usr/local/bin/debsecan-filtered.sh` | The deployed filter script |
| `/var/cache/debsecan-filtered/` | Cache directory |
| `/var/cache/debsecan-filtered/seen-cves.csv` | First-seen / last-seen tracking |
| `/var/cache/debsecan-filtered/triage-skip.csv` | Debian-triaged CVE skip list |
| `/var/log/msmtp.log` | SMTP send log |
| `/etc/mail.rc` | System mail.rc — installer adds `set sendmail=/usr/bin/msmtp` |

## Re-installation / Overwrite

Running `setup-cve-alerts.sh` again will cleanly overwrite all previous configuration. The script is designed to be safe to re-run at any time.

### Files re-written on every run

Every configuration file is written using truncate-and-replace (`cat > file`):

- `/etc/msmtprc` — SMTP relay configuration
- `/etc/apticron/apticron.conf` — apticron notification settings
- `/etc/cron.d/debsecan-report` — cron schedule for daily CVE scan
- `/usr/local/bin/debsecan-filtered.sh` — filter script (copied and `sed`-replaced with new email values)

### Idempotent operations

- `apt-get install -y` skips already-installed packages with no side effects.
- The `/etc/mail.rc` `set sendmail` entry is deduplicated automatically — the old line is removed via `sed` before the new one is appended.
- Component status checks and test emails confirm the new configuration works.

### Re-upload files first

The installer removes itself and the `debsecan-filtered.sh` source file from the upload directory as its final cleanup step. To re-run, you must re-fetch both files first:

```bash
git pull   # if you cloned
# or
scp setup-cve-alerts.sh debsecan-filtered.sh user@server:/root/

sudo bash setup-cve-alerts.sh
```

### Common reasons to re-run

- Updating SMTP credentials (e.g., password rotation)
- Changing sender or recipient email addresses
- Deploying an updated version of the filter script
- Switching SMTP providers
- Re-verifying the setup after major system changes

## Uninstallation

The simplest path is the bundled uninstaller:

```bash
sudo bash uninstall.sh
```

It walks through each removal step interactively and lets you skip individual steps. To run it non-interactively:

```bash
# Remove everything except packages
sudo REMOVE_ALL=1 bash uninstall.sh

# Remove everything including packages
sudo REMOVE_ALL=1 REMOVE_PACKAGES=1 bash uninstall.sh
```

### Manual uninstallation

If you'd rather do it by hand, run these as root. Each step is independent — skip any you want to keep.

```bash
# 1. Remove the cron job
rm -f /etc/cron.d/debsecan-report

# 2. Remove the filter script
rm -f /usr/local/bin/debsecan-filtered.sh

# 3. Remove the filter cache
rm -rf /var/cache/debsecan-filtered

# 4. Remove SMTP configuration (contains credentials)
rm -f /etc/msmtprc

# 5. Remove apticron configuration
rm -f /etc/apticron/apticron.conf

# 6. Remove sendmail override from /etc/mail.rc
sed -i '/^set sendmail/d' /etc/mail.rc

# 7. (Optional) Remove SMTP log
rm -f /var/log/msmtp.log

# 8. (Optional) Remove packages
#    Only do this if no other services on this host depend on msmtp.
apt-get remove --purge msmtp msmtp-mta mailutils apticron debsecan
```

After uninstallation, the system will no longer send CVE or package update alerts. If `msmtp` was the only mail handler configured on this system, removing it will also disable any other mail-dependent services — verify before removing packages.
