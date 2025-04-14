#!/bin/bash

# Configuration
LOG_FILE="/var/log/podman_auto_update.log"
LOCK_FILE="/var/lock/podman_auto_update.lock"
DEBUG=true  # Enable detailed debugging

# Debug function
log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo "$(date) - DEBUG: $1" | tee -a "$LOG_FILE"
    fi
}

# Create lock directory if missing
sudo mkdir -p /var/lock
sudo chmod 1777 /var/lock
exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    echo "$(date) - Auto-update already running. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi
trap 'sudo rm -f "$LOCK_FILE"' EXIT

echo "$(date) - Starting podman auto-update" | tee -a "$LOG_FILE"

# Read Slack Webhook URL from Podman secret
SLACK_WEBHOOK_URL=$(sudo podman run --rm --secret slack-webhook alpine cat /run/secrets/slack-webhook 2>/dev/null)
[[ -z "$SLACK_WEBHOOK_URL" ]] && log_debug "Slack webhook secret not found"

# Execute auto-update with enhanced debugging
log_debug "Running: podman auto-update --format json"
AUTO_UPDATE_OUTPUT=$(sudo podman auto-update --format json 2>&1)
UPDATE_RESULT=$?
log_debug "Raw auto-update output: $AUTO_UPDATE_OUTPUT"

# Parse update results with error handling
if [[ $UPDATE_RESULT -eq 0 ]]; then
    log_debug "Parsing successful auto-update results"
    CONTAINER_SUMMARY=$(echo "$AUTO_UPDATE_OUTPUT" | jq -r '
        .[] | 
        "\(.Container) - \(.Image) - Updated: \(.Updated) - Image ID: \(.ImageID // "N/A")"')
    
    if [[ -z "$CONTAINER_SUMMARY" ]]; then
        CONTAINER_SUMMARY="No containers required updates"
        log_debug "No containers were updated"
    fi
else
    CONTAINER_SUMMARY="Update failed: $(echo "$AUTO_UPDATE_OUTPUT" | grep -i 'error')"
    echo "$(date) - $CONTAINER_SUMMARY" | tee -a "$LOG_FILE"
fi

# Format Slack message with enhanced details
SLACK_MESSAGE=$(jq -n \
    --arg status "$([[ $UPDATE_RESULT -eq 0 ]] && echo "Success" || echo "Failure")" \
    --arg color "$([[ $UPDATE_RESULT -eq 0 ]] && echo "#36a64f" || echo "#ff0000")" \
    --arg containers "$(echo "$CONTAINER_SUMMARY" | sed 's/"/\\"/g' | awk '{print "* " $0}')" \
    --arg count "$(echo "$CONTAINER_SUMMARY" | grep -c 'Updated: true')" \
'{
    text: "Podman Auto-Update Report",
    attachments: [
        {
            color: $color,
            fields: [
                {
                    title: "Update Status",
                    value: $status,
                    short: true
                },
                {
                    title: "Containers Checked",
                    value: ($containers | split("* ") | length -1),
                    short: true
                },
                {
                    title: "Containers Updated",
                    value: ($count | if . == "0" then "None" else . end),
                    short: true
                }
            ]
        },
        {
            color: "#439FE0",
            text: ($containers | if . == "* " then "* No container updates" else . end)
        }
    ]
}')

# Enhanced debug output
echo "Generated Slack Message:"
echo "$SLACK_MESSAGE" | jq .

# Send to Slack with error handling
curl -X POST \
    -H 'Content-type: application/json' \
    --data "$SLACK_MESSAGE" \
    "$SLACK_WEBHOOK_URL" || echo "$(date) - Failed to send Slack notification" | tee -a "$LOG_FILE"

echo "$(date) - Notification sent" | tee -a "$LOG_FILE"
