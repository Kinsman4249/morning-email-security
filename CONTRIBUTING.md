# Contributing to morning-email-security

Thanks for considering a contribution! This is a small project and the process is intentionally lightweight.

## How to report a bug

Open an issue using the **Bug report** template. Please include:

- OS and version (`cat /etc/os-release`)
- The version of this project you're running (commit SHA or release tag)
- The exact command you ran
- The full error output (redact SMTP passwords, recipient addresses if you'd rather)
- Relevant log excerpts:
  - `/var/log/msmtp.log`
  - `journalctl -u cron --since "1 hour ago"` (if a cron run failed)
  - Output of `sudo /usr/local/bin/debsecan-filtered.sh --test` (with sensitive data redacted)

## How to propose a feature

Open an issue using the **Feature request** template. Describe the use case before the implementation - knowing *why* is more useful than *what* in early discussion.

## How to submit a change

1. **Fork** the repo and create a feature branch (`git checkout -b feat/short-description`).
2. **Make your change.** Keep changes focused - one logical change per PR.
3. **Test it.**
   - For installer changes: spin up a clean Debian 12 or Ubuntu 24.04 VM/container and run `sudo bash setup-cve-alerts.sh` end-to-end. Confirm both setup emails arrive.
   - For filter changes: run `sudo /usr/local/bin/debsecan-filtered.sh --test` against a host with known CVEs. Compare output before/after.
4. **Lint it.** Run [`shellcheck`](https://www.shellcheck.net/) locally:
   ```bash
   shellcheck setup-cve-alerts.sh debsecan-filtered.sh uninstall.sh
   ```
   The CI pipeline runs the same check on PRs.
5. **Update documentation.** If your change alters behavior visible to users, update `README.md`, `docs/SETUP_GUIDE.md`, and `CHANGELOG.md` (under `[Unreleased]`).
6. **Open a PR** against `main`. Fill in the PR template.

## Coding conventions

- **Bash:** target Bash 5+ (Debian 11 ships 5.1). Use `set -eo pipefail` at the top of every script. Prefer `[[ ]]` over `[ ]`. Quote all variable expansions.
- **Comments:** explain *why*, not *what*. The Phase 1-9 banner comments in `debsecan-filtered.sh` are a good model.
- **No new dependencies** without strong justification - the appeal of this project is the small, predictable surface area (`msmtp`, `apticron`, `debsecan`, plus core utilities).
- **No telemetry, ever.** This is a security tool. It must not phone home.

## Commit messages

Conventional Commits style is preferred but not required:

```
feat: add --quiet flag to debsecan-filtered.sh
fix: correct apticron config path on Ubuntu 24.04
docs: clarify SMTP2GO port options
```

Keep the subject under 72 characters. Add a body if the change isn't obvious from the diff.

## Releases

Maintainers cut releases by tagging `vX.Y.Z` on `main`. The `release.yml` workflow auto-creates the GitHub Release and attaches the scripts as downloadable assets. Pre-1.0 versioning rules:

- `0.X.0` for any user-visible change
- `0.X.Y` for bug-fix-only patch releases

After 1.0, standard SemVer applies.
