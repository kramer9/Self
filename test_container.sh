#!/usr/bin/env bash

# Usage: sudo ./test_container.sh <container_name> <image:tag>
# Example: sudo ./test_container.sh test-container nginx:1.23

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: sudo $0 <container_name> <image:tag>"
    exit 1
fi

CONTAINER_NAME="$1"
IMAGE="$2"
UNIT_FILE="container-${CONTAINER_NAME}.service"
UNIT_PATH="/etc/systemd/system/$UNIT_FILE"

# Clean up previous runs
if podman container exists "$CONTAINER_NAME"; then
    podman rm -f "$CONTAINER_NAME"
fi
if [[ -f "$UNIT_PATH" ]]; then
    systemctl disable --now "$UNIT_FILE" || true
    rm -f "$UNIT_PATH"
    systemctl daemon-reload
fi

# Pull the latest image for the tag
podman pull "$IMAGE"

REPO="${IMAGE%%:*}"
TAG="${IMAGE##*:}"

# Get the remote digest for the tag
REMOTE_DIGEST=$(skopeo inspect docker://docker.io/library/$REPO:$TAG | jq -r .Digest)

# Get all available digests for this repo (multi-arch aware)
DIGESTS=$(skopeo inspect --raw docker://docker.io/library/$REPO:$TAG | jq -r '.manifests[]?.digest' 2>/dev/null || true)

# Pick an older digest that is NOT the current one
OLDER_DIGEST=""
for d in $DIGESTS; do
    if [[ "$d" != "$REMOTE_DIGEST" ]]; then
        OLDER_DIGEST="$d"
        break
    fi
done

if [[ -n "$OLDER_DIGEST" ]]; then
    echo "Pulling and tagging older digest: $OLDER_DIGEST"
    podman pull "docker.io/library/$REPO@$OLDER_DIGEST"
    podman rmi "$IMAGE" || true
    podman tag "docker.io/library/$REPO@$OLDER_DIGEST" "$IMAGE"
else
    echo "No older digest found or only one digest available. Proceeding with current image."
fi

# Show local and remote digests for verification
echo "Local image digest for $IMAGE:"
podman images --digests | grep "$IMAGE"
echo "Remote digest for $IMAGE:"
echo "$REMOTE_DIGEST"

# Create the container and systemd unit
podman run -d --name "$CONTAINER_NAME" --label "io.containers.autoupdate=registry" "$IMAGE"
podman generate systemd --name "$CONTAINER_NAME" --files --new
podman rm -f "$CONTAINER_NAME"
mv "$UNIT_FILE" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now "$UNIT_FILE"

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

