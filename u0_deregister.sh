#!/bin/bash

# Usage: ./u0_deregister.sh /full/path/to/executable

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 /full/path/to/executable"
  exit 1
fi

EXEC="$1"

EXEC_NAME=$(basename "$EXEC")
SERVICE_NAME=$(echo "$EXEC_NAME" | tr '[:upper:]' '[:lower:]')
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

if [ ! -f "$SERVICE_FILE" ]; then
  echo "$0: Service file '$SERVICE_FILE' does not exist."
  exit 0
fi

echo "Stopping service $SERVICE_NAME if running..."
systemctl stop "$SERVICE_NAME" || true

echo "Disabling service $SERVICE_NAME..."
systemctl disable "$SERVICE_NAME" || true

echo "Removing systemd service file: $SERVICE_FILE"
rm -f "$SERVICE_FILE"

# SELinux recover
if command -v semanage >/dev/null 2>&1; then
  echo "Removing SELinux exception for $EXEC ..."
  semanage fcontext -d "$EXEC" 2>/dev/null || true
  restorecon -v "$EXEC" || true
fi

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "$0: Service '$SERVICE_NAME' deregistered."
