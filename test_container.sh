#!/usr/bin/env bash

# Usage: sudo ./test_container.sh <container_name> <image:tag>
# Example: sudo ./test_container.sh test-container nginx:latest

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: sudo $0 <container_name> <image:tag>"
    exit 1
fi

CONTAINER_NAME="$1"
IMAGE="$2"
UNIT_FILE="container-${CONTAINER_NAME}.service"
UNIT_PATH="/etc/systemd/system/$UNIT_FILE"

for cmd in podman jq; do
    command -v $cmd >/dev/null 2>&1 || { echo "Error: $cmd not found in PATH"; exit 1; }
done

# Ensure image is fully qualified for Podman
if [[ "$IMAGE" != *"/"* ]]; then
    IMAGE="docker.io/library/$IMAGE"
    echo "No registry specified, using Docker Hub: $IMAGE"
fi

if podman container exists "$CONTAINER_NAME"; then
    echo "Removing previous container $CONTAINER_NAME..."
    podman rm -f "$CONTAINER_NAME" || { echo "Failed to remove container $CONTAINER_NAME"; exit 1; }
fi

if [[ -f "$UNIT_PATH" ]]; then
    echo "Disabling and removing previous systemd unit $UNIT_FILE..."
    systemctl disable --now "$UNIT_FILE" || echo "Warning: Could not disable $UNIT_FILE"
    rm -f "$UNIT_PATH" || { echo "Failed to remove $UNIT_PATH"; exit 1; }
    systemctl daemon-reload
fi

# Pull the image (first version)
echo "Pulling initial image $IMAGE..."
podman pull "$IMAGE" || { echo "Failed to pull image $IMAGE"; exit 1; }

# Create the container with the local auto-update policy
echo "Creating container $CONTAINER_NAME with local auto-update policy..."
podman run -d --name "$CONTAINER_NAME" --label "io.containers.autoupdate=local" "$IMAGE" || { echo "Failed to create container $CONTAINER_NAME"; exit 1; }

if ! podman container exists "$CONTAINER_NAME"; then
    echo "Error: Container $CONTAINER_NAME was not created successfully."
    exit 1
fi

echo "Generating systemd unit file for $CONTAINER_NAME..."
GENERATED_UNIT_FILE=$(podman generate systemd --name "$CONTAINER_NAME" --files --new | grep '\.service$' | head -n1)
if [[ ! -f "$GENERATED_UNIT_FILE" ]]; then
    echo "Error: Systemd unit file $GENERATED_UNIT_FILE was not generated."
    podman rm -f "$CONTAINER_NAME" || true
    exit 1
fi

echo "Removing temporary container $CONTAINER_NAME (systemd will manage it)..."
podman rm -f "$CONTAINER_NAME" || echo "Warning: Could not remove container $CONTAINER_NAME"

echo "Moving unit file $GENERATED_UNIT_FILE to $UNIT_PATH..."
mv "$GENERATED_UNIT_FILE" "$UNIT_PATH" || { echo "Failed to move unit file to $UNIT_PATH"; exit 1; }

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Enabling and starting systemd unit $UNIT_FILE..."
systemctl enable --now "$UNIT_FILE" || { echo "Failed to enable/start $UNIT_FILE"; exit 1; }

if ! systemctl is-active --quiet "$UNIT_FILE"; then
    echo "Error: Systemd unit $UNIT_FILE is not active."
    systemctl status "$UNIT_FILE"
    exit 1
fi

# Simulate a local image update: build a trivial new image and tag it as the same image name
echo "Simulating a local image update for $IMAGE by building a new image with a different digest..."
TMP_DOCKERFILE=$(mktemp)
cat > "$TMP_DOCKERFILE" <<EOF
FROM $IMAGE
LABEL testupdate=$(date +%s)
EOF

podman build -t "$IMAGE" -f "$TMP_DOCKERFILE" . || { echo "Failed to build updated image for $IMAGE"; rm -f "$TMP_DOCKERFILE"; exit 1; }
rm -f "$TMP_DOCKERFILE"

# Run podman auto-update in dry-run mode and capture output
echo "===== Podman Auto-Update Findings ====="
UPDATE_JSON=$(podman auto-update --dry-run --format json)

if [[ -z "$UPDATE_JSON" || "$UPDATE_JSON" == "[]" ]]; then
    echo "No containers or pods checked for auto-update."
else
    echo "Checked units:"
    echo "$UPDATE_JSON" | jq -r '.[] | "- \(.Unit) (\(.ContainerName // "N/A"))"'

    echo ""
    echo "Units needing update:"
    NEEDS_UPDATE=$(echo "$UPDATE_JSON" | jq -r '.[] | select(.Updated == "pending") | "- \(.Unit) (\(.ContainerName // "N/A"))"')
    if [[ -z "$NEEDS_UPDATE" ]]; then
        echo "None"
    else
        echo "$NEEDS_UPDATE"
    fi
fi
echo "======================================="
