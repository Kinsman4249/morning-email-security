#!/bin/bash
# debsecan-filtered
#
# PURPOSE
# -------
# Actionable CVE alerting using *only* Debian's local debsecan judgement.
# No Debian Security Tracker API calls are used.
# No <no-dsa>/<ignored> logic is applied.
#
# This script intentionally trusts Debian Security Team decisions as
# reflected in debsecan output for the installed suite.
#
# DESIGN PRINCIPLES
# -----------------
# - Quiet by default
# - Deterministic
# - Cron-safe
# - No external network calls
# - Actionable only
#
# BUCKET LOGIC
# ------------
# Bucket A (Patchable):
#   - Fix available in Debian repos (--only-fixed)
#   - AND one of:
#       * remotely exploitable
#       * high / critical urgency
#       * affected package is network-listening
#
# Bucket B (Unpatched):
#   - No fix available
#   - Affected package is network-listening
#   - Source-package expansion applied
#   - CVEs triaged by Debian as no-dsa, ignored, end-of-life,
#     not-affected, or postponed are excluded
#
# CACHING
# -------
# /var/cache/debsecan-filtered/seen-cves.csv
# Tracks first_seen / last_seen for actionable CVEs only.
# Cache is wiped on fresh install by setup script.
#
# FLAGS
# -----
# --test          Always send email
# --flush-cache   Remove cache and exit

set -o pipefail

log() { echo "[debsecan-filtered] $*" >&2; }

SUITE=$(. /etc/os-release && echo "${VERSION_CODENAME}")
FROM_EMAIL="__FROM_EMAIL__"
TO_EMAIL="__TO_EMAIL__"
HOSTNAME=$(hostname -f)
TODAY=$(date +%F)
CACHE_DIR="/var/cache/debsecan-filtered"
SEEN_CSV="$CACHE_DIR/seen-cves.csv"
IS_TEST=""

for arg in "$@"; do
    case "$arg" in
        --test) IS_TEST="--test" ;;
        --flush-cache)
            log "Flushing cache $CACHE_DIR"
            rm -rf "$CACHE_DIR"
            exit 0
            ;;
    esac
done

mkdir -p "$CACHE_DIR"

log "Debian debsecan local judgement only (no tracker API)"
log "Suite: $SUITE"
log "Host:  $HOSTNAME"

# -------------------------------------------------------------------
# Phase 1 — Collect CVE data
# -------------------------------------------------------------------
ALL_FIXED=$(debsecan --suite "$SUITE" --only-fixed --format detail 2>/dev/null || true)
ALL_VULNS=$(debsecan --suite "$SUITE" --format detail 2>/dev/null || true)

# -------------------------------------------------------------------
# Phase 2 — Build unfixed list
# -------------------------------------------------------------------
FIXED_KEYS=$(echo "$ALL_FIXED" | awk '/^CVE-/{print $1" "$2}')
ALL_UNFIXED=$(echo "$ALL_VULNS" | awk -v fixed="$FIXED_KEYS" '
BEGIN{
    n=split(fixed,a,"\n"); for(i=1;i<=n;i++) f[a[i]]=1
}
/^CVE-/ {k=$1" "$2; keep=!(k in f)}
keep {print}
')

# -------------------------------------------------------------------

# -------------------------------------------------------------------
# Phase 2b — Strip Debian-triaged CVEs from unfixed list
# -------------------------------------------------------------------
UNFIXED_PRE=$(echo "$ALL_UNFIXED" | grep -c '^CVE-' || true)

ALL_UNFIXED=$(echo "$ALL_UNFIXED" | awk '
/^CVE-/ {
    if(buf != "" && !skip) printf "%s", buf
    buf = $0"\n"; skip = 0; next
}
{
    buf = buf $0"\n"
    line = tolower($0)
    if(line ~ /no-dsa|ignored|end-of-life|not-affected|postponed/) skip = 1
}
END { if(buf != "" && !skip) printf "%s", buf }
')

UNFIXED_POST=$(echo "$ALL_UNFIXED" | grep -c '^CVE-' || true)
STRIPPED=$((UNFIXED_PRE - UNFIXED_POST))
log "Stripped $STRIPPED Debian-triaged CVEs from unfixed list ($UNFIXED_PRE -> $UNFIXED_POST)"
# Phase 3 — Detect listening packages + source expansion
# -------------------------------------------------------------------
declare -A LISTEN
while read -r p; do
    exe=$(readlink -f /proc/$p/exe 2>/dev/null) || continue
    pkg=$(dpkg -S "$exe" 2>/dev/null | cut -d: -f1) || continue
    LISTEN[$pkg]=1
done < <(ss -tlnp 2>/dev/null | grep -oP 'pid=\K\d+')

# Expand by source package
ALL_PKG_SRC=$(dpkg-query -W -f '${Package}\t${Source}\n' 2>/dev/null)
declare -A EXPANDED
for p in "${!LISTEN[@]}"; do
    src=$(dpkg-query -W -f '${Source}\n' "$p" 2>/dev/null | awk '{print $1}')
    [ -z "$src" ] && src="$p"
    echo "$ALL_PKG_SRC" | awk -F'\t' -v s="$src" '{split($2,a," "); if(a[1]==s) print $1}' | while read -r b; do
        EXPANDED[$b]=1
    done
done

LISTEN_PKGS=$(printf "%s\n" "${!EXPANDED[@]}")

# -------------------------------------------------------------------
# Phase 4 — Bucket filtering
# -------------------------------------------------------------------
filter_bucket_a() {
    echo "$ALL_FIXED" | awk -v pkgs="$LISTEN_PKGS" '
    BEGIN{split(pkgs,p,"\n"); for(i in p) l[p[i]]=1}
    /^CVE-/ {
        buf=$0"\n"; keep=0; pkg=$2; line=tolower($0)
        if(line~/remotely exploitable/) keep=1
        if(line~/high urgency|critical urgency/) keep=1
        if(pkg in l) keep=1
        next
    }
    {buf=buf $0"\n"}
    keep{printf "%s",buf}
    '
}

filter_bucket_b() {
    echo "$ALL_UNFIXED" | awk -v pkgs="$LISTEN_PKGS" '
    BEGIN{split(pkgs,p,"\n"); for(i in p) l[p[i]]=1}
    /^CVE-/ {buf=$0"\n"; keep=($2 in l); next}
    {buf=buf $0"\n"}
    keep{printf "%s",buf}
    '
}

BUCKET_A=$(filter_bucket_a)
BUCKET_B=$(filter_bucket_b)

COUNT_A=$(echo "$BUCKET_A" | grep -c '^CVE-' || true)
COUNT_B=$(echo "$BUCKET_B" | grep -c '^CVE-' || true)
TOTAL=$((COUNT_A+COUNT_B))

# -------------------------------------------------------------------
# Phase 5 — Cache update
# -------------------------------------------------------------------
if [ "$TOTAL" -gt 0 ]; then
    echo "cve_id,package,bucket,first_seen,last_seen" > "$SEEN_CSV"
    for l in $(echo "$BUCKET_A" | awk '/^CVE-/{print $1" "$2}'); do
        set -- $l; echo "$1,$2,A,$TODAY,$TODAY" >> "$SEEN_CSV"
    done
    for l in $(echo "$BUCKET_B" | awk '/^CVE-/{print $1" "$2}'); do
        set -- $l; echo "$1,$2,B,$TODAY,$TODAY" >> "$SEEN_CSV"
    done
fi

# -------------------------------------------------------------------
# Phase 6 — Email
# -------------------------------------------------------------------
if [ "$TOTAL" -eq 0 ] && [ "$IS_TEST" != "--test" ]; then
    log "No actionable CVEs"
    exit 0
fi

{
    echo "From: $FROM_EMAIL"
    echo "To: $TO_EMAIL"
    echo "Subject: [debsecan] $TOTAL actionable CVE(s) - $HOSTNAME"
    echo
    echo "Bucket A (patchable): $COUNT_A"
    echo "Bucket B (unpatched, listening): $COUNT_B"
    echo
    [ "$COUNT_A" -gt 0 ] && echo "$BUCKET_A"
    [ "$COUNT_B" -gt 0 ] && echo "$BUCKET_B"
} | msmtp "$TO_EMAIL"

log "Done"
