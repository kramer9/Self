#!/bin/bash

# Configuration
LOG_FILE="/var/log/podman_auto_update.log"
CONTAINER_SUMMARY=""

# Read Slack Webhook URL from Secret
SLACK_WEBHOOK_URL=$(sudo podman run --rm --secret slack-webhook alpine cat /run/secrets/slack-webhook)

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Auto-update containers with rollback on failure
echo "$(date) - Starting podman auto-update"
AUTO_UPDATE_OUTPUT=$(sudo podman auto-update --format json)
UPDATE_RESULT=$?

# Parse update results
if [[ $UPDATE_RESULT -eq 0 ]]; then
    CONTAINER_SUMMARY=$(echo "$AUTO_UPDATE_OUTPUT" | jq -r '.[] | "\(.Container) - \(.Updated)"')
    echo "$(date) - Update successful"
else
    CONTAINER_SUMMARY="Update failed with error code $UPDATE_RESULT"
    echo "$(date) - $CONTAINER_SUMMARY"
fi

# Format Slack message
SLACK_MESSAGE=$(cat <<EOF
{
    "text": "Podman Auto-Update Report",
    "attachments": [
        {
            "color": "$([[ $UPDATE_RESULT -eq 0 ]] && echo "#36a64f" || echo "#ff0000")",
            "fields": [
                {
                    "title": "Update Status",
                    "value": "$([[ $UPDATE_RESULT -eq 0 ]] && echo "Success" || echo "Failure")",
                    "short": true
                },
                {
                    "title": "Affected Containers",
                    "value": "$(echo "$CONTAINER_SUMMARY" | awk '{print $1}' | uniq | wc -l)",
                    "short": true
                }
            ]
        },
        {
            "color": "#439FE0",
            "text": "$(echo "$CONTAINER_SUMMARY" | sed 's/"/\\"/g' | awk '{print "* " $0}')"
        }
    ]
}
EOF
)

# Send to Slack
curl -X POST \
    -H 'Content-type: application/json' \
    -H 'Content-type: application/json' \
    --data "$SLACK_MESSAGE" \
    "$SLACK_WEBHOOK_URL"

echo "$(date) - Slack notification sent"