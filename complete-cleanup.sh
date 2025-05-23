#!/bin/bash
# Complete cleanup script for Dokploy-Podman
# This script removes all Dokploy-Podman components to allow a fresh installation

echo "===== Dokploy-Podman Cleanup ====="
echo "This script will remove all Dokploy-Podman components."
echo "Press CTRL+C now to abort, or wait 5 seconds to continue..."
sleep 5

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    echo "Try: sudo $0" >&2
    exit 1
fi

echo "Stopping and removing all Dokploy-Podman containers..."
systemctl stop dokploy.service dokploy-traefik.service dokploy-postgres.service dokploy-redis.service pod-dokploy-pod.service 2>/dev/null || true
systemctl disable dokploy.service dokploy-traefik.service dokploy-postgres.service dokploy-redis.service pod-dokploy-pod.service 2>/dev/null || true

podman stop dokploy dokploy-traefik dokploy-postgres dokploy-redis 2>/dev/null || true
podman rm -f dokploy dokploy-traefik dokploy-postgres dokploy-redis 2>/dev/null || true
podman pod stop dokploy-pod 2>/dev/null || true
podman pod rm -f dokploy-pod 2>/dev/null || true
podman network rm dokploy-network 2>/dev/null || true

echo "Removing systemd service files..."
rm -f /etc/systemd/system/dokploy.service /etc/systemd/system/dokploy-traefik.service /etc/systemd/system/dokploy-postgres.service /etc/systemd/system/dokploy-redis.service /etc/systemd/system/pod-dokploy-pod.service 2>/dev/null || true
systemctl daemon-reload

echo "Removing Docker-to-Podman mapping..."
rm -f /usr/local/bin/docker 2>/dev/null || true
rm -f /etc/profile.d/docker-podman-alias.sh 2>/dev/null || true

echo "Do you want to remove Podman completely? (y/n)"
read -r remove_podman

if [[ "$remove_podman" =~ ^[Yy]$ ]]; then
    echo "Removing Podman..."
    if [ -f /etc/debian_version ]; then
        apt-get remove -y podman podman-compose 2>/dev/null || true
    elif [ -f /etc/redhat-release ]; then
        dnf remove -y podman podman-compose 2>/dev/null || true
    fi
    
    # echo "Removing Podman configuration files..."
    # rm -rf /etc/containers /var/lib/containers 2>/dev/null || true
fi

echo "Do you want to remove all Dokploy data? This will delete all application data! (y/n)"
read -r remove_data

if [[ "$remove_data" =~ ^[Yy]$ ]]; then
    echo "Removing Dokploy data..."
    rm -rf /etc/dokploy /var/lib/dokploy 2>/dev/null || true
fi

echo "===== Cleanup Complete ====="
echo "You can now run a fresh installation with ./install-podman.sh"
