#!/bin/bash
# ============================================================
# CVE Alert Stack Uninstaller
#
# Reverses every change made by setup-cve-alerts.sh.
# Each step is independent — answer N to skip a step.
#
# Usage:
#   sudo bash uninstall.sh
#
# Non-interactive mode (remove everything except packages):
#   sudo REMOVE_ALL=1 bash uninstall.sh
#
# Non-interactive mode (remove everything INCLUDING packages):
#   sudo REMOVE_ALL=1 REMOVE_PACKAGES=1 bash uninstall.sh
# ============================================================

set -eo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: must be run as root (try: sudo bash uninstall.sh)"
    exit 1
fi

# ============================================================
# Confirmation helper
# ============================================================
confirm() {
    local prompt="$1"
    local default="${2:-Y}"

    if [ "${REMOVE_ALL:-}" = "1" ]; then
        return 0
    fi

    local default_label="[Y/n]"
    [ "$default" = "N" ] && default_label="[y/N]"

    read -rp "  ${prompt} ${default_label}: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

echo ""
echo "==> CVE Alert Stack Uninstaller"
echo "    This will reverse the changes made by setup-cve-alerts.sh."
echo ""

# ============================================================
# Step 1: Remove cron job
# ============================================================
if [ -f /etc/cron.d/debsecan-report ]; then
    if confirm "Remove daily debsecan cron job (/etc/cron.d/debsecan-report)?"; then
        rm -f /etc/cron.d/debsecan-report
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 2: Remove filter script
# ============================================================
if [ -f /usr/local/bin/debsecan-filtered ]; then
    if confirm "Remove filter script (/usr/local/bin/debsecan-filtered)?"; then
        rm -f /usr/local/bin/debsecan-filtered
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 3: Remove cache directory
# ============================================================
if [ -d /var/cache/debsecan-filtered ]; then
    if confirm "Remove filter cache (/var/cache/debsecan-filtered)?"; then
        rm -rf /var/cache/debsecan-filtered
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 4: Remove SMTP configuration
# ============================================================
if [ -f /etc/msmtprc ]; then
    echo ""
    echo "    NOTE: /etc/msmtprc contains your SMTP password."
    if confirm "Remove SMTP configuration (/etc/msmtprc)?"; then
        rm -f /etc/msmtprc
        echo "    Removed."
    else
        echo "    Skipped (credentials still on disk at /etc/msmtprc)."
    fi
fi

# ============================================================
# Step 5: Remove apticron configuration
# ============================================================
if [ -f /etc/apticron/apticron.conf ]; then
    if confirm "Remove apticron configuration (/etc/apticron/apticron.conf)?"; then
        rm -f /etc/apticron/apticron.conf
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 6: Remove sendmail override from /etc/mail.rc
# ============================================================
if [ -f /etc/mail.rc ] && grep -q "^set sendmail" /etc/mail.rc 2>/dev/null; then
    if confirm "Remove msmtp sendmail override from /etc/mail.rc?"; then
        sed -i '/^set sendmail/d' /etc/mail.rc
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 7: Remove SMTP log
# ============================================================
if [ -f /var/log/msmtp.log ]; then
    if confirm "Remove SMTP log (/var/log/msmtp.log)?" "N"; then
        rm -f /var/log/msmtp.log
        echo "    Removed."
    else
        echo "    Skipped."
    fi
fi

# ============================================================
# Step 8: Remove packages (optional, off by default)
# ============================================================
echo ""
echo "    NOTE: Removing msmtp will disable any other services on this host"
echo "    that rely on it as a mail transport. Verify before continuing."

REMOVE_PKGS_DEFAULT="N"
[ "${REMOVE_PACKAGES:-}" = "1" ] && REMOVE_PKGS_DEFAULT="Y"

if confirm "Remove packages (msmtp msmtp-mta mailutils apticron debsecan)?" "$REMOVE_PKGS_DEFAULT"; then
    apt-get remove --purge -y msmtp msmtp-mta mailutils apticron debsecan
    echo "    Packages removed."
else
    echo "    Skipped."
fi

echo ""
echo "==> Uninstall complete."
echo "    The system will no longer send CVE or package update alerts."
