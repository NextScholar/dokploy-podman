#!/bin/bash

install_dokploy() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    # check if is Mac OS
    if [ "$(uname)" = "Darwin" ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    # check if is running inside a container
    if [ -f /.podmanenv ] || [ -f /.dockerenv ]; then
        echo "This script must be run on a host machine, not in a container" >&2
        exit 1
    fi

    # check if something is running on port 80
    if ss -tulnp | grep ':80 ' >/dev/null; then
        echo "Error: something is already running on port 80" >&2
        exit 1
    fi

    # check if something is running on port 443
    if ss -tulnp | grep ':443 ' >/dev/null; then
        echo "Error: something is already running on port 443" >&2
        exit 1
    fi

    command_exists() {
      command -v "$@" > /dev/null 2>&1
    }

    # Check if Podman is installed, if not install it
    if command_exists podman; then
      echo "Podman already installed"
    else
      echo "Installing Podman..."
      
      # Detect the operating system
      if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y podman
        # Try to install podman-compose if available
        apt-get install -y podman-compose || echo "podman-compose not available, continuing..."
      elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        dnf -y install podman 
        # Try to install podman-compose if available
        dnf -y install podman-compose || echo "podman-compose not available, continuing..."
      else
        echo "Unsupported operating system. Please install Podman manually."
        exit 1
      fi
    fi

    # Check Podman version
    PODMAN_VERSION=$(podman --version | awk '{print $3}')
    echo "Podman version: $PODMAN_VERSION"

    # Check and enable podman.socket if needed (for systemd systems)
    if command_exists systemctl; then
        if systemctl list-unit-files | grep -q "podman.socket"; then
            echo "Enabling and starting podman.socket..."
            systemctl enable --now podman.socket
        fi
    fi

    # Determine the correct socket path
    if [ -S /run/podman/podman.sock ]; then
        PODMAN_SOCKET="/run/podman/podman.sock"
    elif [ -S /var/run/podman/podman.sock ]; then
        PODMAN_SOCKET="/var/run/podman/podman.sock"
    else
        echo "Podman socket not found. Creating socket..."
        # Try to start the socket
        systemctl enable --now podman.socket 2>/dev/null || true
        sleep 3
        
        # Check again for socket
        if [ -S /run/podman/podman.sock ]; then
            PODMAN_SOCKET="/run/podman/podman.sock"
        elif [ -S /var/run/podman/podman.sock ]; then
            PODMAN_SOCKET="/var/run/podman/podman.sock"
        else
            echo "Error: Cannot find Podman socket. Please check your Podman installation."
            exit 1
        fi
    fi
    
    echo "Using Podman socket at: $PODMAN_SOCKET"

    get_ip() {
        local ip=""
        
        # Try IPv4 first
        # First attempt: ifconfig.io
        ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
        
        # Second attempt: icanhazip.com
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
        fi
        
        # Third attempt: ipecho.net
        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
        fi

        # If no IPv4, try IPv6
        if [ -z "$ip" ]; then
            # Try IPv6 with ifconfig.io
            ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
            
            # Try IPv6 with icanhazip.com
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
            fi
            
            # Try IPv6 with ipecho.net
            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
            fi
        fi

        if [ -z "$ip" ]; then
            echo "Error: Could not determine server IP address automatically (neither IPv4 nor IPv6)." >&2
            echo "Please set the ADVERTISE_ADDR environment variable manually." >&2
            echo "Example: export ADVERTISE_ADDR=<your-server-ip>" >&2
            exit 1
        fi

        echo "$ip"
    }

    get_private_ip() {
        ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"

    if [ -z "$advertise_addr" ]; then
        echo "ERROR: We couldn't find a private IP address."
        echo "Please set the ADVERTISE_ADDR environment variable manually."
        echo "Example: export ADVERTISE_ADDR=192.168.1.100"
        exit 1
    fi
    echo "Using advertise address: $advertise_addr"

    # Clean up old resources if they exist
    echo "Cleaning up any existing resources..."
    podman pod rm -f dokploy-pod 2>/dev/null || true
    podman network rm -f dokploy-network 2>/dev/null || true
    podman rm -f dokploy-postgres dokploy-redis dokploy dokploy-traefik 2>/dev/null || true
    
    # Create a Podman network with improved parameters
    podman network create dokploy-network --driver bridge
    echo "Network created: dokploy-network"
    
    # Create a Podman pod for Dokploy services
    podman pod create --name dokploy-pod -p 3000:3000 -p 5432:5432 -p 6379:6379 --network dokploy-network
    echo "Dokploy pod created"

    # Create directories for persistent data
    mkdir -p /etc/dokploy
    chmod 777 /etc/dokploy
    mkdir -p /etc/dokploy/traefik/dynamic
    mkdir -p /var/lib/dokploy/postgres
    mkdir -p /var/lib/dokploy/redis
    
    # Ensure proper permissions
    chmod -R 777 /var/lib/dokploy
    
    # Create and set proper permissions for acme.json
    touch /etc/dokploy/traefik/acme.json
    chmod 600 /etc/dokploy/traefik/acme.json
    
    # Run PostgreSQL in the pod
    echo "Starting PostgreSQL container..."
    podman run -d \
        --pod dokploy-pod \
        --name dokploy-postgres \
        -e POSTGRES_USER=dokploy \
        -e POSTGRES_DB=dokploy \
        -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        -v /var/lib/dokploy/postgres:/var/lib/postgresql/data:Z \
        docker.io/library/postgres:16

    # Run Redis in the pod
    echo "Starting Redis container..."
    podman run -d \
        --pod dokploy-pod \
        --name dokploy-redis \
        -v /var/lib/dokploy/redis:/data:Z \
        docker.io/library/redis:7

    # Wait for database to be ready
    echo "Waiting for database to be ready..."
    sleep 10

    # Run Dokploy in the pod with IP-based connection strings
    echo "Starting Dokploy container..."
    podman run -d \
        --pod dokploy-pod \
        --name dokploy \
        --privileged \
        -v /sys:/sys:rshared \
        -v /proc:/proc:rshared \
        -v /run:/run:rshared \
        -v /var/lib/containers:/var/lib/containers:rshared \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock \
        -v /etc/dokploy:/etc/dokploy:Z \
        -e ADVERTISE_ADDR=$advertise_addr \
        -e DATABASE_URL="postgres://dokploy:amukds4wi9001583845717ad2@127.0.0.1:5432/dokploy" \
        -e POSTGRES_HOST=127.0.0.1 \
        -e POSTGRES_USER=dokploy \
        -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        -e POSTGRES_DB=dokploy \
        -e POSTGRES_PORT=5432 \
        -e REDIS_HOST=127.0.0.1 \
        -e REDIS_PORT=6379 \
        -e DOCKER_HOST=unix://${PODMAN_SOCKET} \
        ghcr.io/nextscholar/dokploy-podman:latest

    # Create default Traefik configuration file if it doesn't exist
    if [ ! -f /etc/dokploy/traefik/traefik.yml ]; then
        cat > /etc/dokploy/traefik/traefik.yml << EOF
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@nextscholar.site
      storage: /etc/dokploy/traefik/acme.json
      httpChallenge:
        entryPoint: web

providers:
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true
  docker:
    endpoint: "unix://${PODMAN_SOCKET}"
    exposedByDefault: false
EOF
    fi

    # Create a Traefik container (use host network mode for proper port binding)
    echo "Starting Traefik container..."
    podman run -d \
        --name dokploy-traefik \
        --restart always \
        --network host \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml:Z \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic:Z \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock:ro \
        -v /etc/dokploy/traefik:/etc/dokploy/traefik:Z \
        docker.io/library/traefik:v3.1.2

    # Connect Traefik to the dokploy network
    podman network connect dokploy-network dokploy-traefik || true

    # Set up Docker to Podman adapter (commented out to avoid conflicts with monitoring)
    echo "Skipping Docker to Podman adapter setup - causes issues with monitoring..."
    # bash "$(dirname "$0")/setup-docker-alias.sh"

    # Create Traefik configuration for nextscholar.site
    if [ ! -f /etc/dokploy/traefik/dynamic/nextscholar-site.yml ]; then
        cat > /etc/dokploy/traefik/dynamic/nextscholar-site.yml << EOF
http:
  routers:
    dokploy:
      rule: "Host(\`nextscholar.site\`) || Host(\`www.nextscholar.site\`)"
      service: "dokploy"
      entryPoints:
        - "websecure"
      tls:
        certResolver: "letsencrypt"
  
  services:
    dokploy:
      loadBalancer:
        servers:
          - url: "http://${advertise_addr}:3000"
EOF
    fi

    # Create simplified systemd service files
    mkdir -p /etc/systemd/system
    
    # Pod service
    cat > /etc/systemd/system/pod-dokploy-pod.service << EOF
[Unit]
Description=Podman pod-dokploy-pod service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/run/containers/storage /var/lib/dokploy

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/bash -c '/usr/bin/sudo /usr/bin/podman pod exists dokploy-pod || /usr/bin/sudo /usr/bin/podman pod create --name dokploy-pod -p 3000:3000 -p 5432:5432 -p 6379:6379 --network dokploy-network'
ExecStart=/bin/bash -c '/usr/bin/sudo /usr/bin/podman pod inspect dokploy-pod -f \"{{.State}}\" | grep -q Running || /usr/bin/sudo /usr/bin/podman pod start dokploy-pod'
ExecStop=/usr/bin/sudo /usr/bin/podman pod stop -t 10 dokploy-pod
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

    # Traefik service
    cat > /etc/systemd/system/dokploy-traefik.service << EOF
[Unit]
Description=Podman container-dokploy-traefik service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target pod-dokploy-pod.service
After=network-online.target pod-dokploy-pod.service
RequiresMountsFor=/run/containers/storage /var/lib/dokploy

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=always
TimeoutStopSec=70
ExecStartPre=-/usr/bin/sudo /usr/bin/podman rm -f dokploy-traefik
ExecStartPre=/usr/bin/sudo /usr/bin/chmod 777 /run/podman/podman.sock
ExecStart=/usr/bin/sudo /usr/bin/podman run --name dokploy-traefik --restart always --network host -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml:Z -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic:Z -v ${PODMAN_SOCKET}:/var/run/docker.sock:ro -v /etc/dokploy/traefik:/etc/dokploy/traefik:Z docker.io/library/traefik:v3.1.2
ExecStop=/usr/bin/sudo /usr/bin/podman stop -t 10 dokploy-traefik
Type=simple

[Install]
WantedBy=default.target
EOF

    # Dokploy service
    cat > /etc/systemd/system/dokploy.service << EOF
[Unit]
Description=Podman container-dokploy service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target pod-dokploy-pod.service dokploy-postgres.service dokploy-redis.service
After=network-online.target pod-dokploy-pod.service dokploy-postgres.service dokploy-redis.service
RequiresMountsFor=/run/containers/storage /var/lib/dokploy

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=-/usr/bin/sudo /usr/bin/podman rm -f dokploy
ExecStart=/usr/bin/sudo /usr/bin/podman run --pod dokploy-pod --name dokploy -v ${PODMAN_SOCKET}:/var/run/docker.sock:ro -v /etc/dokploy:/etc/dokploy:Z -e ADVERTISE_ADDR=${advertise_addr} -e DATABASE_URL=postgres://dokploy:amukds4wi9001583845717ad2@127.0.0.1:5432/dokploy -e POSTGRES_HOST=127.0.0.1 -e POSTGRES_USER=dokploy -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 -e POSTGRES_DB=dokploy -e POSTGRES_PORT=5432 -e REDIS_HOST=127.0.0.1 -e REDIS_PORT=6379 ghcr.io/nextscholar/dokploy-podman:latest
ExecStop=/usr/bin/sudo /usr/bin/podman stop -t 10 dokploy
Type=simple

[Install]
WantedBy=default.target
EOF

    # Postgres service
    cat > /etc/systemd/system/dokploy-postgres.service << EOF
[Unit]
Description=Podman container-dokploy-postgres service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target pod-dokploy-pod.service
After=network-online.target pod-dokploy-pod.service
RequiresMountsFor=/run/containers/storage /var/lib/dokploy

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=-/usr/bin/sudo /usr/bin/podman rm -f dokploy-postgres
ExecStart=/usr/bin/sudo /usr/bin/podman run --pod dokploy-pod --name dokploy-postgres -e POSTGRES_USER=dokploy -e POSTGRES_DB=dokploy -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 -v /var/lib/dokploy/postgres:/var/lib/postgresql/data:Z docker.io/library/postgres:16
ExecStop=/usr/bin/sudo /usr/bin/podman stop -t 10 dokploy-postgres
Type=simple

[Install]
WantedBy=default.target
EOF

    # Redis service
    cat > /etc/systemd/system/dokploy-redis.service << EOF
[Unit]
Description=Podman container-dokploy-redis service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target pod-dokploy-pod.service
After=network-online.target pod-dokploy-pod.service
RequiresMountsFor=/run/containers/storage /var/lib/dokploy

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=-/usr/bin/sudo /usr/bin/podman rm -f dokploy-redis
ExecStart=/usr/bin/sudo /usr/bin/podman run --pod dokploy-pod --name dokploy-redis -v /var/lib/dokploy/redis:/data:Z docker.io/library/redis:7
ExecStop=/usr/bin/sudo /usr/bin/podman stop -t 10 dokploy-redis
Type=simple

[Install]
WantedBy=default.target
EOF

    # Enable and start the services with proper ordering
    systemctl daemon-reload
    
    echo "Starting services..."
    systemctl enable --now pod-dokploy-pod.service
    sleep 5
    
    systemctl enable --now dokploy-postgres.service
    sleep 5
    
    systemctl enable --now dokploy-redis.service
    sleep 5
    
    systemctl enable --now dokploy.service
    sleep 5
    
    systemctl enable --now dokploy-traefik.service

    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    NC="\033[0m" # No Color

    format_ip_for_url() {
        local ip="$1"
        if echo "$ip" | grep -q ':'; then
            # IPv6
            echo "[${ip}]"
        else
            # IPv4
            echo "${ip}"
        fi
    }

    public_ip="${ADVERTISE_ADDR:-$(get_ip)}"
    formatted_addr=$(format_ip_for_url "$public_ip")
    echo ""
    printf "${GREEN}Congratulations, Dokploy-Podman is installed!${NC}\n"
    printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
    printf "${YELLOW}Please go to http://${formatted_addr}:3000${NC}\n\n"
    printf "${BLUE}If you want to make Dokploy available at a domain, configure DNS and update /etc/dokploy/traefik/dynamic/nextscholar-site.yml${NC}\n"
    printf "${YELLOW}To check the status of services, run: systemctl status dokploy.service${NC}\n"
}

update_dokploy() {
    # Determine the correct socket path
    if [ -S /run/podman/podman.sock ]; then
        PODMAN_SOCKET="/run/podman/podman.sock"
    elif [ -S /var/run/podman/podman.sock ]; then
        PODMAN_SOCKET="/var/run/podman/podman.sock"
    else
        echo "Podman socket not found. Continuing with default path..."
        PODMAN_SOCKET="/var/run/podman/podman.sock"
    fi

    get_private_ip() {
        ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"

    echo "Updating Dokploy-Podman..."
    
    # Pull the latest image
    podman pull ghcr.io/nextscholar/dokploy-podman:latest

    # Update the container
    podman stop dokploy
    podman rm dokploy
    
    podman run -d \
        --pod dokploy-pod \
        --name dokploy \
        --privileged \
        -v /sys:/sys:rshared \
        -v /proc:/proc:rshared \
        -v /run:/run:rshared \
        -v /var/lib/containers:/var/lib/containers:rshared \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock \
        -v /etc/dokploy:/etc/dokploy:Z \
        -e ADVERTISE_ADDR=$advertise_addr \
        -e DATABASE_URL=postgres://dokploy:amukds4wi9001583845717ad2@127.0.0.1:5432/dokploy \
        -e POSTGRES_HOST=127.0.0.1 \
        -e POSTGRES_USER=dokploy \
        -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        -e POSTGRES_DB=dokploy \
        -e POSTGRES_PORT=5432 \
        -e REDIS_HOST=127.0.0.1 \
        -e REDIS_PORT=6379 \
        -e DOCKER_HOST=unix://${PODMAN_SOCKET} \
        ghcr.io/nextscholar/dokploy-podman:latest

    echo "Dokploy-Podman has been updated to the latest version."
}

# Main script execution
if [ "$1" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi