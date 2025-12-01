#!/bin/bash

# Usage: ./u1_register.sh /full/path/to/executable

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 /full/path/to/executable"
  exit 1
fi

EXEC="$1"

if [ ! -f "$EXEC" ]; then
  echo "$0: '$EXEC' does not exist."
  exit 2
fi
if [ ! -x "$EXEC" ]; then
  echo "$0: '$EXEC' is not executable."
  exit 3
fi

EXEC_NAME=$(basename "$EXEC")
SERVICE_NAME=$(echo "$EXEC_NAME" | tr '[:upper:]' '[:lower:]')
WORKDIR=$(dirname "$EXEC")

# SELinux exception
if command -v semanage >/dev/null 2>&1 && command -v restorecon >/dev/null 2>&1; then
  echo "Setting SELinux type for $EXEC so systemd can execute it..."
  semanage fcontext -a -t bin_t "$EXEC" 2>/dev/null || true
  restorecon -v "$EXEC"
fi

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Creating systemd service: $SERVICE_FILE"

tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Service for $EXEC_NAME
After=network.target

[Service]
Type=simple
ExecStart=$EXEC
WorkingDirectory=$WORKDIR
Restart=on-failure
RestartSec=5
KillMode=control-group
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "$0: Service '$SERVICE_NAME' registered."
echo "  systemctl start $SERVICE_NAME"
echo "  systemctl stop $SERVICE_NAME"
echo "  systemctl enable --now $SERVICE_NAME"
echo "  systemctl disable $SERVICE_NAME"
echo "  systemctl status $SERVICE_NAME"
