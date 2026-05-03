# Troubleshooting Cookbook

Common failure modes and how to diagnose them. If you find a new failure mode, please [open an issue](https://github.com/Kinsman4249/morning-email-security/issues/new/choose) so we can add it here.

## "I never got the setup emails"

The installer sends two emails as its final step. If neither arrived after `setup-cve-alerts.sh` completed:

### Step 1: Check the SMTP log

```bash
sudo tail -50 /var/log/msmtp.log
```

The log shows every send attempt with the SMTP response. Common patterns:

| Log message | Meaning | Fix |
| --- | --- | --- |
| `host=... tls=on auth=on user=... ... smtpstatus=535` | Authentication rejected | Wrong username/password — check `/etc/msmtprc` |
| `smtpstatus=550 ... sender ... not verified` | Sender not verified with provider | Verify the `From:` address with your SMTP provider |
| `smtpstatus=421` or connection timeouts | Network/firewall block | Check outbound port access (try `nc -vz <smtp-host> <port>`) |
| Log file is empty | `msmtp` never ran | See "msmtp not invoked" below |

### Step 2: Verify SMTP credentials manually

```bash
sudo msmtp -d -t <<EOF
From: alerts@yourdomain.com
To: admin@yourdomain.com
Subject: manual test

body
EOF
```

`-d` shows the SMTP conversation. Look for `235 Authentication succeeded` and `250 OK` after `DATA`.

### Step 3: Check sender verification

Most providers silently drop messages from unverified senders. Log into your provider's dashboard and check the verification status of the `From:` address. For domain-based verification (Mailgun, SES, Postmark), confirm DNS records are in place: `dig TXT _dmarc.yourdomain.com`, `dig TXT yourdomain.com`, etc.

### Step 4: Check spam folder

If verification looks fine, the email may have been delivered to spam. Search your inbox for `[debsecan]` or the `Subject:` line from the setup summary.

## "msmtp: command not found" or no log file

Means the installer didn't successfully install `msmtp`, or another mail handler is taking precedence.

```bash
which msmtp
# Should print: /usr/bin/msmtp

cat /etc/mail.rc | grep sendmail
# Should include: set sendmail=/usr/bin/msmtp

dpkg -l | grep -E 'msmtp|apticron|debsecan'
# Should show all three installed
```

If any are missing, re-run the installer (`sudo bash setup-cve-alerts.sh`).

## "debsecan: error: cannot get vulnerabilities" or network errors

`debsecan` downloads the Debian Security Tracker database from `security-tracker.debian.org`. If that fails:

```bash
# Check network access
curl -fIs https://security-tracker.debian.org/tracker/debsecan/release/1/ | head

# Check that the suite is detected correctly
. /etc/os-release && echo "$VERSION_CODENAME"
# Should print bookworm, bullseye, jammy, noble, etc.

# Manual debsecan run with errors visible
sudo debsecan --suite "$(. /etc/os-release && echo $VERSION_CODENAME)" --format report 2>&1 | head -20
```

Common causes:
- **No outbound HTTPS** — corporate firewall blocking the security tracker. Configure an HTTPS proxy via the `https_proxy` env var in `/etc/cron.d/debsecan-report`.
- **Unrecognized suite** — happens on Debian-derivatives that don't match the Debian Security Tracker suite naming. Override by adding `--suite bookworm` (or whichever upstream Debian release your system is based on) to the cron entry.

## "I'm not getting daily emails, but the test email worked"

The cron job is silent if no actionable CVEs exist. Confirm by running the filter manually:

```bash
sudo /usr/local/bin/debsecan-filtered.sh --test
```

`--test` always emails, regardless of result count. If that sends, the daily cron is working — you just have no actionable CVEs (which is the goal, but verify with `--test` periodically).

If the test email DOESN'T arrive, but the setup email did, one of two things is happening:
1. The filter is hitting an error mid-run. Check `journalctl -u cron --since "1 hour ago"` for stderr output.
2. The `From:` or `To:` placeholders weren't substituted correctly. Check `/usr/local/bin/debsecan-filtered.sh`:
   ```bash
   sudo grep -E '^FROM_EMAIL|^TO_EMAIL' /usr/local/bin/debsecan-filtered.sh
   ```
   These should show your real addresses, NOT `__FROM_EMAIL__` / `__TO_EMAIL__`. If they show the placeholders, re-run the installer.

## "Cron isn't running my script"

Check the cron service is running:

```bash
sudo systemctl status cron
```

Inspect cron entries:

```bash
ls -la /etc/cron.d/
sudo cat /etc/cron.d/debsecan-report
```

The `debsecan-report` file should be `chmod 644` and have a final newline. Cron silently ignores files with bad permissions or missing newlines.

Watch cron logs in real time:

```bash
sudo journalctl -u cron -f
```

You should see a line like `(root) CMD (/usr/local/bin/debsecan-filtered.sh)` at 07:00.

## "The filter ran but listening packages are wrong / empty"

Phase 5 of `debsecan-filtered.sh` discovers listening packages via `ss -tlnp`. This requires `ss` to see PIDs, which needs root.

```bash
# Run as root
sudo ss -tlnp

# Verify each PID's executable maps to a package
sudo ss -tlnp | awk '/pid=/ {match($0, /pid=[0-9]+/); print substr($0, RSTART+4, RLENGTH-4)}' | while read pid; do
    exe=$(sudo readlink -f /proc/$pid/exe 2>/dev/null)
    pkg=$(dpkg -S "$exe" 2>/dev/null | cut -d: -f1)
    echo "PID=$pid  EXE=$exe  PKG=$pkg"
done
```

Edge cases:
- **Process running from a non-package binary** (e.g., `/opt/myapp/bin/server`) — `dpkg -S` won't find it, so the package won't be in `LISTEN_MAP`. The filter will not catch CVEs against this. Either install the binary via a `.deb` package or accept the gap.
- **Container runtime listening** — Docker, Podman, etc. The package owning `dockerd` is `docker-ce` or `docker.io`, but the containerized services running on top are NOT discovered by `ss -tlnp` on the host. Run a separate scanner inside containers.

## "The cache is corrupt" / "I see weird CVE counts"

Wipe the cache and start fresh:

```bash
sudo /usr/local/bin/debsecan-filtered.sh --flush-cache
sudo /usr/local/bin/debsecan-filtered.sh --test
```

This rebuilds `triage-skip.csv` and `seen-cves.csv` from scratch. The next email will show every actionable CVE as "new since last run" because the cache has no history yet — that's expected, and counts will normalize on subsequent runs.

## "I'm getting WAY too many Bucket A emails"

By default, Bucket A is broad: patchable AND (remote OR high-urgency OR listening). On a busy server, that can be 30+ CVEs in a typical week.

Two ways to tame it:

1. **Patch them.** That's the point of the alerts. `sudo apt-get upgrade` clears the list.
2. **Tighten the criteria.** Edit `/usr/local/bin/debsecan-filtered.sh`, find the Bucket A awk block in Phase 6, and remove the criteria you don't want. For "listening port only":
   ```awk
   if (line ~ /remotely exploitable/) printing = 1   # delete this line
   if (line ~ /high urgency|critical urgency/) printing = 1   # delete this line
   ```

## "I changed something and now nothing works"

The installer is idempotent. Re-run it:

```bash
# Re-fetch source files (installer removes them after each run)
git pull

# Re-install
sudo bash setup-cve-alerts.sh
```

This clobbers all generated config files with known-good versions and rebuilds the cache. Your SMTP credentials are preserved if you prefill them via env vars.

## "How do I uninstall completely?"

```bash
sudo bash uninstall.sh
```

Or follow the manual steps in [`SETUP_GUIDE.md`](SETUP_GUIDE.md#manual-uninstallation).

## Still stuck?

[Open an issue](https://github.com/Kinsman4249/morning-email-security/issues/new/choose) with:
- Your OS (`cat /etc/os-release`)
- Your version of this project (commit SHA or tag)
- The exact command you ran
- Full error output (with SMTP passwords redacted)
- Output of `sudo /usr/local/bin/debsecan-filtered.sh --test 2>&1 | head -100`
