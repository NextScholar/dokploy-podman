#!/bin/bash
# Setup Docker to Podman mapping
# This script maps Docker commands to Podman for compatibility

echo "===== Setting Up Docker to Podman Mapping ====="

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    echo "Try: sudo $0" >&2
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# Check if Podman is installed
if ! command_exists podman; then
    echo "Podman is not installed. Please install it first."
    echo "Try: ./install-podman.sh"
    exit 1
fi

# Check if our adapter script exists
ADAPTER_SCRIPT_PATH="/home/azureuser/dokploy-podman/podman-adapter.sh"
if [ ! -f "$ADAPTER_SCRIPT_PATH" ]; then
    echo "Podman adapter script not found at $ADAPTER_SCRIPT_PATH"
    exit 1
fi

# Make sure adapter script is executable
chmod +x "$ADAPTER_SCRIPT_PATH"

# Create symlink for docker command
DOCKER_PATH="/usr/local/bin/docker"
ln -sf "$ADAPTER_SCRIPT_PATH" "$DOCKER_PATH"
echo "Created symlink from $ADAPTER_SCRIPT_PATH to $DOCKER_PATH"

# Set up system-wide alias
ALIAS_FILE="/etc/profile.d/docker-podman-alias.sh"
cat > "$ALIAS_FILE" << 'EOF'
# Alias docker to use podman adapter
if [ ! -x "$(command -v docker)" ] || [ "$(realpath $(command -v docker))" == "/usr/local/bin/docker" ]; then
    alias docker='/usr/local/bin/docker'
fi
EOF

chmod +x "$ALIAS_FILE"
echo "Added system-wide alias in $ALIAS_FILE"

# Apply immediately for current session
source "$ALIAS_FILE"

# Verify setup
echo "Testing Docker to Podman mapping..."
$DOCKER_PATH --version

# Success message
echo ""
echo "✅ Docker to Podman mapping set up successfully!"
echo "Any 'docker' command will now be handled by Podman via the adapter."
echo ""
echo "To apply changes in the current terminal:"
echo "  source $ALIAS_FILE"
echo ""
echo "You may need to log out and back in for the changes to take full effect."
