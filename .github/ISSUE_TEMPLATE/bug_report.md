---
name: Bug report
about: Report a problem with the installer, the filter, or the documentation
title: "[bug] "
labels: bug
assignees: ''
---

## What happened

<!-- A clear and concise description of the problem. -->

## What you expected to happen

<!-- Describe the expected behavior. -->

## Steps to reproduce

1.
2.
3.

## Environment

- OS and version (output of `cat /etc/os-release`):
- Debian suite (output of `. /etc/os-release && echo $VERSION_CODENAME`):
- Project version (release tag or commit SHA):

## Output / logs

<details>
<summary>Output of the failing command</summary>

```text
<paste the full output here, with sensitive data redacted>
```

</details>

<details>
<summary>Relevant SMTP log (<code>sudo cat /var/log/msmtp.log</code>)</summary>

```text
<paste, redact passwords / recipient addresses if you prefer>
```

</details>

<details>
<summary>Filter output (<code>sudo /usr/local/bin/debsecan-filtered.sh --test 2>&1 | head -100</code>)</summary>

```text
<paste here>
```

</details>

## Anything else?

<!-- Other context, screenshots, related issues, your hypothesis on the cause. -->
