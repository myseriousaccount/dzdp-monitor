#!/bin/bash
#
# DZDP v2 Migration Monitor
# Checks if DoubleZero migrated to new API model.
# Sends Discord webhook alert if changes detected.
#
# Usage: DISCORD_WEBHOOK_URL="..." bash monitor.sh
#

set -uo pipefail

# Config
WEBHOOK="${DISCORD_WEBHOOK_URL:-}"
THRESHOLD_BYTES=100  # alert if v2 endpoint returns > 100 bytes
NEW_FIELDS=("edge_stake" "decentralization_points" "conversion_rate" "device_points")

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

send_alert() {
    local message="$1"
    log "${YELLOW}ALERT:${NC} $message"

    if [[ -n "$WEBHOOK" ]]; then
        # Discord expects {"content": "..."}
        local json
        json=$(printf '{"content": "%s"}' "$(echo "$message" | sed 's/"/\\"/g; s/\n/\\n/g')")

        curl -s -X POST -H "Content-Type: application/json" \
            -d "$json" "$WEBHOOK" > /dev/null

        log "Alert sent to Discord"
    else
        log "${RED}WARN:${NC} DISCORD_WEBHOOK_URL not set, alert printed only"
    fi
}

# === Check 1: /api/dzdp/v2 size ===
log "Checking /api/dzdp/v2..."
V2_SIZE=$(curl -s -o /tmp/dzdp_v2.json -w "%{size_download}" \
    "https://doublezero.xyz/api/dzdp/v2" \
    -H "User-Agent: Mozilla/5.0" || echo "0")

log "  size = $V2_SIZE bytes (threshold: $THRESHOLD_BYTES)"

if [[ "$V2_SIZE" -gt "$THRESHOLD_BYTES" ]]; then
    send_alert "🚨 **DZDP v2 Migration Detected!** /api/dzdp/v2 now returns ${V2_SIZE} bytes (was 0). Check the API immediately and update Pools Advisor integration."
    log "${GREEN}Triggered v2 alert${NC}"
fi

# === Check 2: /api/dzdp/v2/calculator/data size ===
log "Checking /api/dzdp/v2/calculator/data..."
V2_CALC_SIZE=$(curl -s -o /tmp/dzdp_v2_calc.json -w "%{size_download}" \
    "https://doublezero.xyz/api/dzdp/v2/calculator/data" \
    -H "User-Agent: Mozilla/5.0" || echo "0")

log "  size = $V2_CALC_SIZE bytes"

if [[ "$V2_CALC_SIZE" -gt "$THRESHOLD_BYTES" ]]; then
    send_alert "🚨 **DZDP v2 calculator data live!** /api/dzdp/v2/calculator/data now returns ${V2_CALC_SIZE} bytes (was 0)."
    log "${GREEN}Triggered v2 calculator alert${NC}"
fi

# === Check 3: New fields in /api/dzdp/v1 validator schema ===
log "Checking /api/dzdp/v1 schema for new NEW-model fields..."
curl -s "https://doublezero.xyz/api/dzdp/v1" -H "User-Agent: Mozilla/5.0" -o /tmp/dzdp_v1.json

if command -v jq &> /dev/null; then
    # Get keys of first validator
    KEYS=$(jq -r '.data.validators[0] | keys | .[]' /tmp/dzdp_v1.json 2>/dev/null || echo "")

    FOUND_FIELDS=""
    for field in "${NEW_FIELDS[@]}"; do
        if echo "$KEYS" | grep -q "^${field}$"; then
            FOUND_FIELDS="${FOUND_FIELDS}- ${field}\n"
        fi
    done

    if [[ -n "$FOUND_FIELDS" ]]; then
        send_alert "🚨 **DZDP v1 schema updated with NEW-model fields:**\n${FOUND_FIELDS}\nThis may indicate v1 endpoint now serves the new model. Verify the API response and update integration."
        log "${GREEN}Triggered schema-change alert${NC}"
    else
        log "  no new fields found (still old schema)"
    fi
else
    log "${YELLOW}WARN:${NC} jq not installed, skipping schema check"
fi

log "${GREEN}Done.${NC} v2=${V2_SIZE}B, v2_calc=${V2_CALC_SIZE}B"
