# Security Policy

## Supported Versions

This project is currently pre-1.0. Only the most recent release receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.5.x   | :white_check_mark: |
| < 0.5   | :x:                |

## Reporting a Vulnerability

If you find a security issue in this project, **please do not file a public GitHub issue**.

Instead, open a private GitHub Security Advisory:

1. Go to the [Security tab](https://github.com/Kinsman4249/morning-email-security/security) of this repository.
2. Click **"Report a vulnerability"**.
3. Provide as much detail as possible: affected version, reproduction steps, impact, and any suggested mitigation.

You should receive an acknowledgment within a few business days. If the issue is confirmed, a fix will be developed privately and released as a patch version. You'll be credited in the release notes (or anonymously, if you prefer).

## Scope

In-scope:

- Vulnerabilities in `setup-cve-alerts.sh`, `debsecan-filtered`, or `uninstall.sh`
- Insecure default configurations written by the installer (`/etc/msmtprc`, `/etc/apticron/apticron.conf`, `/etc/cron.d/debsecan-report`, etc.)
- Any path that could allow a non-root user to read SMTP credentials, modify the filter, or escalate privileges

Out of scope:

- Vulnerabilities in upstream Debian packages (`msmtp`, `apticron`, `debsecan`) — please report those to the Debian security team
- Vulnerabilities in your SMTP provider — report those to the provider directly
- General hardening suggestions for your own host (use a feature request issue instead)

## Note on the project's purpose

This project surfaces CVE alerts. It is itself a piece of security infrastructure, so we take vulnerability reports seriously and prioritize them above all other work.
