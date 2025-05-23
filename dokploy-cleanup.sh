#!/bin/bash

echo "Starting complete Dokploy cleanup..."

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    echo "Try: sudo $0" >&2
    exit 1
fi

# Stop and disable systemd services if they exist
if command -v systemctl &> /dev/null; then
    echo "Stopping and disabling systemd services..."
    systemctl stop dokploy-traefik.service dokploy.service dokploy-redis.service dokploy-postgres.service pod-dokploy-pod.service 2>/dev/null || true
    systemctl disable dokploy-traefik.service dokploy.service dokploy-redis.service dokploy-postgres.service pod-dokploy-pod.service 2>/dev/null || true
    
    # Remove service files
    rm -f /etc/systemd/system/dokploy-traefik.service /etc/systemd/system/dokploy.service /etc/systemd/system/dokploy-redis.service /etc/systemd/system/dokploy-postgres.service /etc/systemd/system/pod-dokploy-pod.service 2>/dev/null || true
    
    systemctl daemon-reload
fi

# Find and kill processes on ports 80 and 443
echo "Checking for processes using ports 80 and 443..."
for PORT in 80 443; do
    PID=$(ss -tulnp | grep ":$PORT " | awk -F"pid=" '{print $2}' | awk -F"," '{print $1}')
    if [ ! -z "$PID" ]; then
        echo "Killing process $PID on port $PORT"
        kill -9 $PID 2>/dev/null || true
    fi
done

# Stop and remove all Dokploy-related containers
if command -v podman &> /dev/null; then
    echo "Removing Podman containers, pods, and networks..."
    podman stop dokploy-traefik dokploy dokploy-redis dokploy-postgres 2>/dev/null || true
    podman rm -f dokploy-traefik dokploy dokploy-redis dokploy-postgres 2>/dev/null || true
    podman pod stop dokploy-pod 2>/dev/null || true
    podman pod rm -f dokploy-pod 2>/dev/null || true
    podman network rm -f dokploy-network 2>/dev/null || true
    
    # Remove volumes
    echo "Removing Podman volumes..."
    podman volume rm dokploy-postgres-database redis-data-volume dokploy-docker-config 2>/dev/null || true
fi

# Also check for Docker containers if Docker is installed
if command -v docker &> /dev/null; then
    echo "Removing Docker containers, services, and networks..."
    docker stop dokploy-traefik dokploy dokploy-redis dokploy-postgres 2>/dev/null || true
    docker rm -f dokploy-traefik dokploy dokploy-redis dokploy-postgres 2>/dev/null || true
    
    # Check if docker service exists and remove them
    if docker service ls 2>/dev/null | grep -q "dokploy"; then
        docker service rm dokploy dokploy-postgres dokploy-redis dokploy-traefik 2>/dev/null || true
    fi
    
    # Leave Docker swarm if in swarm mode
    docker swarm leave --force 2>/dev/null || true
    
    # Remove Docker networks
    docker network rm dokploy-network 2>/dev/null || true
    
    # Remove Docker volumes
    echo "Removing Docker volumes..."
    docker volume rm dokploy-postgres-database redis-data-volume dokploy-docker-config 2>/dev/null || true
fi

# Remove data directories
echo "Removing data directories..."
rm -rf /etc/dokploy/traefik 2>/dev/null || true
rm -rf /etc/dokploy 2>/dev/null || true
rm -rf /var/lib/dokploy 2>/dev/null || true

# Remove Docker-to-Podman adapter
echo "Removing Docker-to-Podman adapter..."
rm -f /usr/local/bin/docker 2>/dev/null || true
rm -f /etc/profile.d/docker-podman-alias.sh 2>/dev/null || true

# Check for and remove Podman if requested
if [ "$1" = "--remove-podman" ]; then
    echo "Removing Podman..."
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get remove -y podman podman-compose
    elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        dnf remove -y podman podman-compose
    fi
fi

# Check again for processes on ports 80 and 443
for PORT in 80 443 3000; do
    if ss -tulnp | grep ":$PORT " >/dev/null; then
        echo "Warning: Port $PORT is still in use. You may need to manually find and stop the process."
        echo "Use these commands to identify the process:"
        echo "  ss -tulnp | grep ':$PORT '"
        echo "  lsof -i :$PORT"
    else
        echo "Port $PORT is now free."
    fi
done

# Print completion message
echo "===== Cleanup completed ====="
echo "The system has been cleaned up and all Dokploy components have been removed."
echo ""
echo "To reinstall Dokploy, run:"
echo "  1. sudo ./install-podman.sh     # Install Podman"
echo "  2. sudo ./docker-to-podman.sh   # Set up Docker-to-Podman mapping"
echo "  3. sudo ./test.sh               # Verify the setup"
echo ""