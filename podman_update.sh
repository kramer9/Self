#!/usr/bin/env bash

# Script: podman-auto-update-report.sh
# Purpose: Simulate podman auto-update, report containers checked and those needing update (with container names).

set -euo pipefail

# 1. Run dry-run to see which containers would be updated
DRY_RUN_JSON=$(sudo podman auto-update --dry-run --format json)

# 2. Extract all checked containers (unit and container name)
ALL_CONTAINERS=$(echo "$DRY_RUN_JSON" | jq -r '.[] | "\(.Unit) (\(.ContainerName // "N/A"))"')
NEEDS_UPDATE_CONTAINERS=$(echo "$DRY_RUN_JSON" | jq -r '.[] | select(.Updated == "pending") | "\(.Unit) (\(.ContainerName // "N/A"))"')

echo "=== Podman Auto-Update Report ==="
echo ""
echo "Containers checked:"
if [[ -z "$ALL_CONTAINERS" ]]; then
    echo "None"
else
    echo "$ALL_CONTAINERS"
fi
echo ""
echo "Containers needing update:"
if [[ -z "$NEEDS_UPDATE_CONTAINERS" ]]; then
    echo "None"
else
    echo "$NEEDS_UPDATE_CONTAINERS"
fi
echo ""
echo "=== End of Report ==="
