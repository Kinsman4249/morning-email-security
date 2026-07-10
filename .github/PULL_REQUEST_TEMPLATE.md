## Summary

<!-- 1-3 bullets describing what this PR changes and why. -->

-
-

## Type of change

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would change existing behavior)
- [ ] Documentation only

## Testing

How did you verify this works?

- [ ] Ran `shellcheck setup-cve-alerts.sh debsecan-filtered.sh uninstall.sh` locally - clean
- [ ] Ran `sudo bash setup-cve-alerts.sh` end-to-end on a clean Debian 12 / Ubuntu 24.04 VM or container
- [ ] Confirmed both setup emails arrived
- [ ] Ran `sudo /usr/local/bin/debsecan-filtered.sh --test` and verified output

<!-- If any of the boxes above don't apply, explain why. -->

## Documentation

- [ ] Updated `README.md` if user-visible behavior changed
- [ ] Updated `docs/SETUP_GUIDE.md` if installation flow changed
- [ ] Updated `docs/ALERT_LOGIC.md` if filter pipeline changed
- [ ] Added a numbered entry to `CHANGELOG.md` under the current round

## Related issues

<!-- Closes #123, refs #456 -->

## Anything else?

<!-- Reviewer notes, follow-up work, screenshots of test emails, etc. -->
