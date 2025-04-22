#!/usr/bin/env bash

# Script: combined_podman_update_slack.sh
# Purpose: Perform podman auto-update and report containers checked and those needing update to Slack.

set -euo pipefail

# Load Bitwarden environment
if [ -f /etc/bitwarden/env ]; then
  source /etc/bitwarden/env
  export BWS_ACCESS_TOKEN # Ensure it's exported for child processes
else
  echo "Error: Environment file /etc/bitwarden/env not found."
  exit 1
fi

# Check if BWS_ACCESS_TOKEN is set
if [ -z "$BWS_ACCESS_TOKEN" ]; then
  echo "Error: BWS_ACCESS_TOKEN is not set."
  exit 1
fi

# Retrieve secret from Bitwarden using the key
WEBHOOK_URL=$(bws secret get 1dd0cfbe-b2b2-4c50-bf8d-b2bc00ea08a4 --output json | jq -r '.value')

# Check if WEBHOOK_URL was retrieved successfully
if [ -z "$WEBHOOK_URL" ]; then
  echo "Error: Failed to retrieve SLACK_WEBHOOK_URL from Bitwarden."
  exit 1
fi

# 1. Run dry-run to see which containers would be updated
DRY_RUN_JSON=$(sudo podman auto-update --dry-run --format json)

# 2. Extract all checked containers (unit and container name)
ALL_CONTAINERS=$(echo "$DRY_RUN_JSON" | jq -r '.[] | "\(.Unit) (\(.ContainerName // "N/A"))"')
NEEDS_UPDATE_CONTAINERS=$(echo "$DRY_RUN_JSON" | jq -r '.[] | select(.Updated == "pending") | "\(.Unit) (\(.ContainerName // "N/A"))"')

# 3. Perform the update
sudo podman auto-update

# 4. Get the updated list of containers needing update (after the update)
DRY_RUN_JSON_POST_UPDATE=$(sudo podman auto-update --dry-run --format json)
NEEDS_UPDATE_CONTAINERS_POST_UPDATE=$(echo "$DRY_RUN_JSON_POST_UPDATE" | jq -r '.[] | select(.Updated == "pending") | "\(.Unit) (\(.ContainerName // "N/A"))"')

# --- Construct the Slack message ---
MESSAGE_HEADER="*Podman Auto-Update Report ($(date +%F))*:"
CHECKED_CONTAINERS="*Containers checked:*\n"
if [[ -z "$ALL_CONTAINERS" ]]; then
  CHECKED_CONTAINERS+="None\n"
else
  CHECKED_CONTAINERS+="$ALL_CONTAINERS\n"
fi

UPDATE_CONTAINERS="*Containers needing update (before update):*\n"
if [[ -z "$NEEDS_UPDATE_CONTAINERS" ]]; then
  UPDATE_CONTAINERS+="None\n"
else
  UPDATE_CONTAINERS+="$NEEDS_UPDATE_CONTAINERS\n"
fi

UPDATE_CONTAINERS_POST_UPDATE_TEXT="*Containers needing update (after update):*\n"
if [[ -z "$NEEDS_UPDATE_CONTAINERS_POST_UPDATE" ]]; then
  UPDATE_CONTAINERS_POST_UPDATE_TEXT+="None\n"
else
  UPDATE_CONTAINERS_POST_UPDATE_TEXT+="$NEEDS_UPDATE_CONTAINERS_POST_UPDATE\n"
fi

FULL_MESSAGE="$MESSAGE_HEADER\n$CHECKED_CONTAINERS\n$UPDATE_CONTAINERS\n$UPDATE_CONTAINERS_POST_UPDATE_TEXT"

# --- Trim message if it exceeds Slack's limit (around 3000 characters) ---
MAX_LENGTH=2900 # Leave some buffer
MESSAGE_LENGTH=${#FULL_MESSAGE}

if [[ "$MESSAGE_LENGTH" -gt "$MAX_LENGTH" ]]; then
  # Truncate and add a warning
  TRUNCATED_MESSAGE="${FULL_MESSAGE:0:$MAX_LENGTH}...\n*Message truncated due to length.*"
  SLACK_MESSAGE="$TRUNCATED_MESSAGE"
else
  SLACK_MESSAGE="$FULL_MESSAGE"
fi

# Send notification to Slack
curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"$SLACK_MESSAGE\"}" \
  "$WEBHOOK_URL"
