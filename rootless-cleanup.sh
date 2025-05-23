#!/bin/bash

echo "Starting rootless Dokploy cleanup..."

# Function to run podman with the right user
run_podman() {
    podman "$@"
}

# Stop and remove all containers
echo "Stopping and removing containers..."
run_podman stop $(run_podman ps -aq) 2>/dev/null || true
run_podman rm $(run_podman ps -aq) 2>/dev/null || true

# Remove all volumes
echo "Removing volumes..."
run_podman volume rm $(run_podman volume ls -q) 2>/dev/null || true

# Remove all pods
echo "Removing pods..."
run_podman pod rm -f $(run_podman pod ls -q) 2>/dev/null || true

# Remove all images
echo "Removing images..."
run_podman rmi -f $(run_podman images -aq) 2>/dev/null || true

# Clean up podman system
echo "Cleaning up podman system..."
run_podman system prune -af --volumes

# Remove temporary and cache directories
echo "Cleaning up temporary files..."
find ~/.local/share/containers -type d -name "*tmp*" -exec rm -rf {} + 2>/dev/null || true

echo "Cleanup complete. You may need to restart podman with: podman system restart"
