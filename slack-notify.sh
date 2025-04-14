#!/bin/bash

# Load Bitwarden environment
if [ -f /etc/bitwarden/env ]; then
    source /etc/bitwarden/env
    export BWS_ACCESS_TOKEN  # Ensure it's exported for child processes
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

# Send notification to Slack
curl -X POST -H 'Content-type: application/json' \
     --data "{\"text\":\"$(date +%F) - System operational after reboot\"}" \
     $WEBHOOK_URL
