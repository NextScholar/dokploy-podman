#!/bin/bash
# This script sets up the Docker-to-Podman adapter by creating a system-wide alias

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Check if we're inside a container
IN_CONTAINER=false
if [ -f /.dockerenv ] || [ -f /.podmanenv ] || grep -q '1:name=podman:' /proc/self/cgroup 2>/dev/null; then
    IN_CONTAINER=true
    echo "Container environment detected."
fi

# Set up the adapter script
ADAPTER_SCRIPT="/usr/local/bin/docker"
PODMAN_ADAPTER="/home/azureuser/dokploy-podman/podman-adapter.sh"

# If we're in a container, check if Docker already points to Podman
if [ "$IN_CONTAINER" = true ] && [ -f "/usr/bin/docker" ]; then
    if grep -q "podman" /usr/bin/docker; then
        echo "Docker is already configured to use Podman inside this container."
        echo "No changes needed."
        exit 0
    fi
fi

# Make sure the adapter script exists
if [ ! -f "$PODMAN_ADAPTER" ]; then
    echo "Error: Podman adapter script not found at $PODMAN_ADAPTER" >&2
    exit 1
fi

# Make it executable
chmod +x "$PODMAN_ADAPTER"

# Create a symlink to our adapter script
ln -sf "$PODMAN_ADAPTER" "$ADAPTER_SCRIPT"
echo "Created symlink from $PODMAN_ADAPTER to $ADAPTER_SCRIPT"

# Verify installation
if [ -L "$ADAPTER_SCRIPT" ] && [ -x "$PODMAN_ADAPTER" ]; then
    echo "✅ Docker-to-Podman adapter installed successfully!"
    echo "All 'docker' commands will now be handled by Podman"
else
    echo "❌ Installation failed. Please check permissions and try again."
    exit 1
fi

# Add an alias in .bashrc for all users
ALIAS_FILE="/etc/profile.d/docker-podman-alias.sh"
cat > "$ALIAS_FILE" << 'EOF'
# Alias docker to use podman adapter
if [ ! -x "$(command -v docker)" ] || [ "$(realpath $(command -v docker))" == "/usr/local/bin/docker" ]; then
    alias docker='/usr/local/bin/docker'
fi
EOF

chmod +x "$ALIAS_FILE"
echo "Added system-wide alias in $ALIAS_FILE"

echo ""
echo "To apply changes immediately, run:"
echo "  source /etc/profile.d/docker-podman-alias.sh"
echo ""
echo "You may need to log out and log back in for the alias to take effect for all shells."
echo "After that, any 'docker' command will be handled by Podman."
