#!/bin/bash
# Setup Podman for rootless usage

echo "===== Setting up Podman for rootless usage ====="

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    echo "Try: sudo $0" >&2
    exit 1
fi

# Get the username to set up
USERNAME="${SUDO_USER:-$USER}"
if [ "$USERNAME" = "root" ]; then
    echo "Please specify a regular user: sudo $0 <username>"
    exit 1
fi

echo "Setting up Podman for user: $USERNAME"

# Create podman group if it doesn't exist
if ! getent group podman > /dev/null; then
    echo "Creating podman group..."
    groupadd podman
fi

# Add user to podman group
echo "Adding user $USERNAME to podman group..."
usermod -aG podman "$USERNAME"

# Create systemd user directory
mkdir -p /etc/systemd/system/podman.socket.d/

# Create drop-in to change socket permissions
cat > /etc/systemd/system/podman.socket.d/override.conf << 'EOF'
[Socket]
SocketMode=0660
SocketUser=root
SocketGroup=podman
EOF

# Reload systemd and restart podman.socket
echo "Reloading systemd and restarting podman.socket..."
systemctl daemon-reload
systemctl restart podman.socket

# Check socket permissions
echo "Checking socket permissions..."
ls -la /run/podman/podman.sock

echo ""
echo "✅ Podman has been configured for rootless usage."
echo "Please log out and log back in, or run the following command to apply changes immediately:"
echo "  newgrp podman"
echo ""
echo "After that, you should be able to run Podman commands without sudo."
echo ""
