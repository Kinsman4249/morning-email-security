# SMTP Provider Quick-Reference

The installer defaults to SMTP2GO, but `morning-email-security` works with any SMTP relay. This doc is a quick lookup table for the most common providers and the gotchas to watch for with each.

> Whichever provider you pick, you need three things:
>
> 1. SMTP host + port
> 2. Username + password (sometimes a separate API key)
> 3. A **verified sender** address (the `From:`)

If your alert emails aren't arriving, the most common cause is an unverified sender - providers silently drop messages from addresses they haven't verified.

## SMTP2GO (default)

| Field | Value |
| --- | --- |
| Host | `mail.smtp2go.com` |
| Port | `2525` (or `587`, `8025`, `25`) |
| Auth | SMTP username + password (set up in dashboard) |
| Sender verification | Domain or single-address verification |

**Notes:** SMTP2GO is the default in `setup-cve-alerts.sh` because their free tier (1,000 emails/month) is generous for a CVE alerting use case (~30 emails/month per host). Port 2525 sidesteps ISPs that block port 25.

```bash
sudo SMTP_HOST="mail.smtp2go.com" \
     SMTP_PORT="2525" \
     SMTP_USER="your-smtp2go-user" \
     SMTP_PASS="your-smtp2go-password" \
     bash setup-cve-alerts.sh
```

## Amazon SES

| Field | Value |
| --- | --- |
| Host | `email-smtp.<region>.amazonaws.com` (e.g. `email-smtp.us-east-1.amazonaws.com`) |
| Port | `587` (STARTTLS) or `465` (TLS wrapper) |
| Auth | SES SMTP credentials - **NOT** your AWS access keys |
| Sender verification | Domain or address verification in SES console |

**Notes:** Generate SES SMTP credentials in the SES console under "SMTP settings" -> "Create SMTP credentials". You'll get a username and password that are derived from an IAM user but distinct from your AWS access key. New accounts start in the SES sandbox - you can only send to verified addresses until you request production access.

```bash
sudo SMTP_HOST="email-smtp.us-east-1.amazonaws.com" \
     SMTP_PORT="587" \
     SMTP_USER="AKIA..." \
     SMTP_PASS="<ses-smtp-password>" \
     bash setup-cve-alerts.sh
```

## Mailgun

| Field | Value |
| --- | --- |
| Host | `smtp.mailgun.org` (US) or `smtp.eu.mailgun.org` (EU) |
| Port | `587` |
| Auth | SMTP username = `postmaster@<your-domain>`, password = SMTP password (NOT API key) |
| Sender verification | Domain verification (DNS-based) |

**Notes:** Mailgun's SMTP password is separate from the API key - find it in the dashboard under "Domains" -> click your domain -> "SMTP credentials". The username includes `postmaster@` followed by the domain you've verified.

```bash
sudo SMTP_HOST="smtp.mailgun.org" \
     SMTP_PORT="587" \
     SMTP_USER="postmaster@mg.yourdomain.com" \
     SMTP_PASS="<mailgun-smtp-password>" \
     bash setup-cve-alerts.sh
```

## Postmark

| Field | Value |
| --- | --- |
| Host | `smtp.postmarkapp.com` |
| Port | `587` (or `25`, `2525`) |
| Auth | Username = your **Server API token**, password = same Server API token |
| Sender verification | Domain (DKIM) or single-address verification |

**Notes:** Postmark uses the Server API token as both username and password - odd but works. Get it from the server's "API Tokens" tab. Postmark is strict about sender verification; expect emails to bounce until your domain or sender is verified.

```bash
sudo SMTP_HOST="smtp.postmarkapp.com" \
     SMTP_PORT="587" \
     SMTP_USER="<server-api-token>" \
     SMTP_PASS="<server-api-token>" \
     bash setup-cve-alerts.sh
```

## SendGrid

| Field | Value |
| --- | --- |
| Host | `smtp.sendgrid.net` |
| Port | `587` |
| Auth | Username = literally the string `apikey`, password = your SendGrid API key |
| Sender verification | Domain authentication or single-sender verification |

**Notes:** The username is always the literal string `apikey`- that's not a placeholder. The password is the API key (starts with `SG.`). Generate it in Settings -> API Keys with at least "Mail Send" permission.

```bash
sudo SMTP_HOST="smtp.sendgrid.net" \
     SMTP_PORT="587" \
     SMTP_USER="apikey" \
     SMTP_PASS="SG.xxxxxxxxxxxxxxxx" \
     bash setup-cve-alerts.sh
```

## Gmail / Google Workspace (App Password)

| Field | Value |
| --- | --- |
| Host | `smtp.gmail.com` |
| Port | `587` (STARTTLS) or `465` (TLS wrapper) |
| Auth | Gmail address + **App Password** (NOT your account password) |
| Sender verification | Must send from the authenticated Gmail address (or a verified Send-As alias) |

**Notes:** You must enable 2-Step Verification on the Google account, then generate an App Password (myaccount.google.com -> Security -> App passwords). Regular account passwords don't work for SMTP. Daily send limits apply: ~500/day for personal Gmail, ~2000/day for Workspace.

For a CVE-alert use case (a few emails per day), this is fine - but it's worth knowing if you plan to deploy to many hosts using the same Gmail account.

```bash
sudo SMTP_HOST="smtp.gmail.com" \
     SMTP_PORT="587" \
     SMTP_USER="alerts@yourdomain.com" \
     SMTP_PASS="<16-char-app-password>" \
     bash setup-cve-alerts.sh
```

## Self-hosted (Postfix relay on another box)

If you already run a Postfix smarthost on your network, point `msmtp` at that:

```bash
sudo SMTP_HOST="mail.internal.example" \
     SMTP_PORT="25" \
     SMTP_USER="" \
     SMTP_PASS="" \
     bash setup-cve-alerts.sh
```

You'll need to edit `/etc/msmtprc` afterward to remove the `auth on` line and the `user`/`password` fields if your relay doesn't require authentication.

## Switching providers later

Re-running the installer with new values cleanly overwrites `/etc/msmtprc`:

```bash
# Re-fetch the source files first (the installer cleans them up after each run)
git pull   # or scp them again

# Re-install with new SMTP creds
sudo SMTP_HOST="<new-host>" \
     SMTP_PORT="<new-port>" \
     SMTP_USER="<new-user>" \
     SMTP_PASS="<new-pass>" \
     FROM_EMAIL="<sender>" \
     TO_EMAIL="<recipient>" \
     bash setup-cve-alerts.sh
```

## Verifying SMTP works

After install, the easiest check is:

```bash
echo "test body" | msmtp -d <to@example.com>
```

`-d` enables debug output so you'll see the SMTP conversation. Look for `250 OK` after `DATA`. If you see auth errors, recheck the password.

For ongoing diagnostics:

```bash
sudo tail -f /var/log/msmtp.log
```

This logs every send attempt with timestamps and SMTP response codes.
