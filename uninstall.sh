#!/bin/bash
# ============================================================
# Uninstall debsecan-filtered.sh CVE Alert Stack
#
# Removes filter script, cron job, and cache.
# Interactively offers to remove configs and packages.
#
# Usage:
#   sudo bash uninstall.sh
# ============================================================

set -eo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

REMOVED=()
SKIPPED=()

echo ""
echo "==> debsecan-filtered.sh Uninstaller"
echo ""

# ------------------------------------------------------------
# Always remove: filter script, cron job, cache
# ------------------------------------------------------------
if [ -f /usr/local/bin/debsecan-filtered.sh ]; then
    rm -f /usr/local/bin/debsecan-filtered.sh
    REMOVED+=("Filter script: /usr/local/bin/debsecan-filtered.sh")
else
    SKIPPED+=("Filter script: /usr/local/bin/debsecan-filtered.sh (not found)")
fi

if [ -f /etc/cron.d/debsecan-report ]; then
    rm -f /etc/cron.d/debsecan-report
    REMOVED+=("Cron job: /etc/cron.d/debsecan-report")
else
    SKIPPED+=("Cron job: /etc/cron.d/debsecan-report (not found)")
fi

if [ -d /var/cache/debsecan-filtered ]; then
    rm -rf /var/cache/debsecan-filtered
    REMOVED+=("Cache: /var/cache/debsecan-filtered/")
else
    SKIPPED+=("Cache: /var/cache/debsecan-filtered/ (not found)")
fi

# ------------------------------------------------------------
# Interactive: msmtp config
# ------------------------------------------------------------
read -rp "==> Remove msmtp config (/etc/msmtprc, sendmail line from /etc/mail.rc)? [y/N]: " ans_msmtp
ans_msmtp="${ans_msmtp:-N}"
if [[ "$ans_msmtp" =~ ^[Yy]$ ]]; then
    if [ -f /etc/msmtprc ]; then
        rm -f /etc/msmtprc
        REMOVED+=("msmtp config: /etc/msmtprc")
    fi
    if [ -f /etc/mail.rc ]; then
        sed -i '/^set sendmail=\/usr\/bin\/msmtp$/d' /etc/mail.rc
        REMOVED+=("Sendmail override removed from /etc/mail.rc")
    fi
else
    SKIPPED+=("msmtp config: kept")
fi

# ------------------------------------------------------------
# Interactive: apticron config
# ------------------------------------------------------------
read -rp "==> Remove apticron config (/etc/apticron/apticron.conf)? [y/N]: " ans_apticron
ans_apticron="${ans_apticron:-N}"
if [[ "$ans_apticron" =~ ^[Yy]$ ]]; then
    if [ -f /etc/apticron/apticron.conf ]; then
        rm -f /etc/apticron/apticron.conf
        REMOVED+=("Apticron config: /etc/apticron/apticron.conf")
    fi
else
    SKIPPED+=("Apticron config: kept")
fi

# ------------------------------------------------------------
# Interactive: remove packages
# ------------------------------------------------------------
read -rp "==> Remove packages (msmtp msmtp-mta mailutils apticron debsecan)? [y/N]: " ans_pkgs
ans_pkgs="${ans_pkgs:-N}"
if [[ "$ans_pkgs" =~ ^[Yy]$ ]]; then
    apt-get remove -y msmtp msmtp-mta mailutils apticron debsecan 2>/dev/null || true
    REMOVED+=("Packages: msmtp msmtp-mta mailutils apticron debsecan")
else
    SKIPPED+=("Packages: kept")
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "==> Uninstall Summary"
echo ""

if [ ${#REMOVED[@]} -gt 0 ]; then
    echo "  Removed:"
    for item in "${REMOVED[@]}"; do
        echo "    ✓ $item"
    done
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "  Skipped:"
    for item in "${SKIPPED[@]}"; do
        echo "    - $item"
    done
fi

echo ""
echo "==> Done."
