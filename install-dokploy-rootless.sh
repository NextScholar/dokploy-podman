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

    # Get the non-root user for rootless Podman
    if [ -n "$SUDO_USER" ]; then
        ACTUAL_USER="$SUDO_USER"
    else
        # Try to determine the non-root user (using a more reliable method)
        ACTUAL_USER=$(who | grep -v root | head -n1 | awk '{print $1}')
        if [ -z "$ACTUAL_USER" ]; then
            # If we can't determine a user and USERNAME env var is set, use that
            if [ -n "$USERNAME" ] && [ "$USERNAME" != "root" ]; then
                ACTUAL_USER="$USERNAME"
            else
                echo "Cannot determine a non-root user for rootless Podman setup."
                echo "Please run this script with sudo or set the USERNAME environment variable."
                exit 1
            fi
        fi
    fi
    
    echo "Setting up for user: $ACTUAL_USER"
    ACTUAL_USER_UID=$(id -u "$ACTUAL_USER")
    ACTUAL_USER_HOME=$(eval echo ~$ACTUAL_USER)

    # Check if Podman is installed, if not install it
    if command_exists podman; then
      echo "Podman already installed"
    else
      echo "Installing Podman..."
      
      # Detect the operating system
      if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y podman slirp4netns fuse-overlayfs uidmap dbus-user-session
        # Try to install podman-compose if available
        apt-get install -y podman-compose || echo "podman-compose not available, continuing..."
      elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora
        dnf -y install podman slirp4netns fuse-overlayfs dbus-daemon
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

    # Set up rootless Podman
    setup_rootless_podman() {
        local username=$1
        
        # Configure subuid and subgid if they don't exist
        if ! grep -q "^${username}:" /etc/subuid; then
            echo "${username}:100000:65536" >> /etc/subuid
        fi
        
        if ! grep -q "^${username}:" /etc/subgid; then
            echo "${username}:100000:65536" >> /etc/subgid
        fi
        
        # Apply required kernel parameters
        echo "user.max_user_namespaces=28633" > /etc/sysctl.d/userns.conf
        sysctl -p /etc/sysctl.d/userns.conf
        
        # Create systemd user directory
        mkdir -p $ACTUAL_USER_HOME/.config/systemd/user
        chown -R ${username}:${username} $ACTUAL_USER_HOME/.config
        
        # Enable linger for the user to allow services to run without login
        loginctl enable-linger ${username}
        
        echo "Rootless Podman setup complete for user: ${username}"
    }

    # Run rootless setup
    setup_rootless_podman "$ACTUAL_USER"

    # Set up socket manually since systemctl --user might not work in all contexts
    echo "Setting up Podman socket for rootless mode..."
    
    # Create the socket activation service manually
    mkdir -p $ACTUAL_USER_HOME/.config/systemd/user
    cat > $ACTUAL_USER_HOME/.config/systemd/user/podman.socket << EOF
[Unit]
Description=Podman API Socket
Documentation=man:podman-system-service(1)

[Socket]
ListenStream=%t/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF

    cat > $ACTUAL_USER_HOME/.config/systemd/user/podman.service << EOF
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-system-service(1)

[Service]
Type=simple
ExecStart=/usr/bin/podman system service

[Install]
WantedBy=default.target
EOF

    chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_USER_HOME/.config/systemd

    # Enable linger again to be sure
    loginctl enable-linger $ACTUAL_USER
    
    # Create the podman socket directory
    mkdir -p /run/user/$ACTUAL_USER_UID/podman
    chown -R $ACTUAL_USER:$ACTUAL_USER /run/user/$ACTUAL_USER_UID
    
    # Start the podman service directly
    su - $ACTUAL_USER -c "XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID podman system service --time=0 unix:///run/user/$ACTUAL_USER_UID/podman/podman.sock &"
    
    # Give it a moment to start
    sleep 5
    
    # Determine the correct socket path for rootless mode
    PODMAN_SOCKET="/run/user/$ACTUAL_USER_UID/podman/podman.sock"
    
    # Wait for socket to become available
    echo "Waiting for Podman socket to become available..."
    for i in {1..10}; do
        if [ -S "$PODMAN_SOCKET" ]; then
            echo "Podman socket is available at: $PODMAN_SOCKET"
            break
        fi
        echo "Waiting for socket ($i/10)..."
        sleep 2
    done
    
    if [ ! -S "$PODMAN_SOCKET" ]; then
        echo "Warning: Podman socket not found at $PODMAN_SOCKET after waiting."
        echo "Will continue with setup, but services might not work correctly."
    fi

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

    # Create directories for persistent data with correct ownership
    echo "Creating required directories..."
    mkdir -p /etc/dokploy
    mkdir -p /etc/dokploy/traefik/dynamic
    mkdir -p /var/lib/dokploy/postgres
    mkdir -p /var/lib/dokploy/redis
    
    # Set ownership to non-root user
    chown -R $ACTUAL_USER:$ACTUAL_USER /etc/dokploy
    chown -R $ACTUAL_USER:$ACTUAL_USER /var/lib/dokploy
    
    # Create and set proper permissions for acme.json
    touch /etc/dokploy/traefik/acme.json
    chmod 600 /etc/dokploy/traefik/acme.json
    chown $ACTUAL_USER:$ACTUAL_USER /etc/dokploy/traefik/acme.json

    # Clean up old resources if they exist
    echo "Cleaning up any existing resources..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman pod rm -f dokploy-pod 2>/dev/null || true"
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman network rm -f dokploy-network 2>/dev/null || true"
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman rm -f dokploy-postgres dokploy-redis dokploy dokploy-traefik 2>/dev/null || true"
    
    # Create a Podman network with improved parameters
    echo "Creating Podman network..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman network create dokploy-network --driver bridge"
    
    # Create a Podman pod for Dokploy services
    echo "Creating Podman pod..."
    # Note: For rootless mode, we use higher ports as non-root users can't bind to privileged ports
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman pod create --name dokploy-pod -p 3000:3000 -p 5432:5432 -p 6379:6379 -p 8080:8080 -p 8443:8443 --network dokploy-network"
    
    # Create port forwarding for privileged ports to unprivileged ports
    echo "Setting up port forwarding (80->8080, 443->8443)..."
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
    
    # Save iptables rules to persist across reboots
    if command_exists iptables-save; then
        if [ -f /etc/debian_version ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        elif [ -f /etc/redhat-release ]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
    fi
    
    # Run PostgreSQL in the pod
    echo "Starting PostgreSQL container..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman run -d \
        --pod dokploy-pod \
        --name dokploy-postgres \
        -e POSTGRES_USER=dokploy \
        -e POSTGRES_DB=dokploy \
        -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        -v /var/lib/dokploy/postgres:/var/lib/postgresql/data:Z \
        docker.io/library/postgres:16"

    # Run Redis in the pod
    echo "Starting Redis container..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman run -d \
        --pod dokploy-pod \
        --name dokploy-redis \
        -v /var/lib/dokploy/redis:/data:Z \
        docker.io/library/redis:7"

    # Wait for database to be ready
    echo "Waiting for database to be ready..."
    for i in {1..15}; do
        if XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman exec -it dokploy-postgres pg_isready -U dokploy -d dokploy" >/dev/null 2>&1; then
            echo "Database is ready!"
            break
        fi
        echo "Waiting for database to initialize ($i/15)..."
        sleep 2
        if [ $i -eq 15 ]; then
            echo "WARNING: Database did not initialize in expected time. Continuing anyway..."
        fi
    done

    # Create default Traefik configuration file if it doesn't exist
    if [ ! -f /etc/dokploy/traefik/traefik.yml ]; then
        cat > /etc/dokploy/traefik/traefik.yml << EOF
entryPoints:
  web:
    address: ":8080"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":8443"

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
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
EOF
        chown $ACTUAL_USER:$ACTUAL_USER /etc/dokploy/traefik/traefik.yml
    fi

    # Set proper permissions for Podman socket to allow Traefik to access it
    echo "Setting proper permissions for Podman socket..."
    chmod 666 ${PODMAN_SOCKET}
    
    # Run Dokploy in the pod with IP-based connection strings
    echo "Starting Dokploy container..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman run -d \
        --pod dokploy-pod \
        --name dokploy \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock:rw \
        -v /etc/dokploy:/etc/dokploy:Z \
        -e ADVERTISE_ADDR=$advertise_addr \
        -e DATABASE_URL=\"postgres://dokploy:amukds4wi9001583845717ad2@127.0.0.1:5432/dokploy\" \
        -e POSTGRES_HOST=127.0.0.1 \
        -e POSTGRES_USER=dokploy \
        -e POSTGRES_PASSWORD=amukds4wi9001583845717ad2 \
        -e POSTGRES_DB=dokploy \
        -e POSTGRES_PORT=5432 \
        -e REDIS_HOST=127.0.0.1 \
        -e REDIS_PORT=6379 \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        ghcr.io/nextscholar/dokploy-podman:latest"

    # Create a Traefik container
    echo "Starting Traefik container..."
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman run -d \
        --name dokploy-traefik \
        --pod dokploy-pod \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml:Z \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic:Z \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock:rw \
        -v /etc/dokploy/traefik:/etc/dokploy/traefik:Z \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        docker.io/library/traefik:v3.1.2"

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
        chown $ACTUAL_USER:$ACTUAL_USER /etc/dokploy/traefik/dynamic/nextscholar-site.yml
    fi

    # Create a system service file for maintenance
    cat > /etc/systemd/system/dokploy-maintenance.service << EOF
[Unit]
Description=Dokploy Maintenance Service
After=network.target

[Service]
Type=oneshot
User=$ACTUAL_USER
Environment="XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID"
ExecStart=/usr/bin/podman pod start dokploy-pod
ExecStart=/usr/bin/podman start dokploy-postgres dokploy-redis dokploy dokploy-traefik
ExecStart=/bin/bash -c 'chmod 666 /run/user/$ACTUAL_USER_UID/podman/podman.sock'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Create a system service for port forwarding
    cat > /etc/systemd/system/dokploy-port-forward.service << EOF
[Unit]
Description=Dokploy Port Forwarding Service
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
ExecStart=/sbin/iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now dokploy-port-forward.service
    systemctl enable dokploy-maintenance.service

    # Create a systemd startup script to ensure the dokploy services start on boot
    cat > /etc/systemd/system/dokploy-startup.service << EOF
[Unit]
Description=Dokploy Startup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman system service --time=0 unix:///run/user/$ACTUAL_USER_UID/podman/podman.sock &"'
ExecStart=/bin/sleep 5
ExecStart=/bin/systemctl start dokploy-maintenance.service
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable dokploy-startup.service

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
    printf "${GREEN}Congratulations, Dokploy-Podman is installed in rootless mode!${NC}\n"
    printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
    printf "${YELLOW}Please go to http://${formatted_addr}:3000${NC}\n\n"
    printf "${BLUE}If you want to make Dokploy available at a domain, configure DNS and update /etc/dokploy/traefik/dynamic/nextscholar-site.yml${NC}\n"
    printf "${YELLOW}To check container status, run: sudo -u $ACTUAL_USER XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID podman ps${NC}\n"
    printf "${BLUE}Note: Port 80 is forwarded to 8080 and port 443 is forwarded to 8443 for rootless operation${NC}\n"
    printf "${YELLOW}Services will automatically start on system boot${NC}\n"
}

update_dokploy() {
    # Get the non-root user for rootless Podman
    if [ -n "$SUDO_USER" ]; then
        ACTUAL_USER="$SUDO_USER"
    else
        # Try to determine the non-root user
        ACTUAL_USER=$(who | grep -v root | head -n1 | awk '{print $1}')
        if [ -z "$ACTUAL_USER" ]; then
            # If we can't determine a user and USERNAME env var is set, use that
            if [ -n "$USERNAME" ] && [ "$USERNAME" != "root" ]; then
                ACTUAL_USER="$USERNAME"
            else
                echo "Cannot determine a non-root user for rootless Podman update."
                echo "Please run this script with sudo or set the USERNAME environment variable."
                exit 1
            fi
        fi
    fi
    
    ACTUAL_USER_UID=$(id -u "$ACTUAL_USER")
    
    # Determine the correct socket path for rootless mode
    PODMAN_SOCKET="/run/user/$ACTUAL_USER_UID/podman/podman.sock"
    if [ ! -S "$PODMAN_SOCKET" ]; then
        echo "Podman socket not found at $PODMAN_SOCKET. Checking alternative locations..."
        if [ -S /run/podman/podman.sock ]; then
            PODMAN_SOCKET="/run/podman/podman.sock"
        elif [ -S /var/run/podman/podman.sock ]; then
            PODMAN_SOCKET="/var/run/podman/podman.sock"
        else
            echo "Podman socket not found. Starting podman socket service..."
            
            # Try to start the socket service
            mkdir -p /run/user/$ACTUAL_USER_UID/podman
            chown -R $ACTUAL_USER:$ACTUAL_USER /run/user/$ACTUAL_USER_UID
            XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman system service --time=0 unix:///run/user/$ACTUAL_USER_UID/podman/podman.sock &"
            sleep 5
            
            # Check if socket is now available
            if [ -S "/run/user/$ACTUAL_USER_UID/podman/podman.sock" ]; then
                PODMAN_SOCKET="/run/user/$ACTUAL_USER_UID/podman/podman.sock"
                echo "Socket is now available at: $PODMAN_SOCKET"
                
                # Verify the socket is working
                if ! XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman info > /dev/null 2>&1"; then
                    echo "ERROR: Podman socket exists but isn't responding correctly."
                    echo "Try manually restarting the podman service with:"
                    echo "loginctl enable-linger $ACTUAL_USER"
                    echo "su - $ACTUAL_USER -c 'systemctl --user enable --now podman.socket'"
                    exit 1
                fi
            else
                echo "ERROR: Podman socket could not be created. Please check Podman installation."
                echo "Try manually starting the Podman socket with:"
                echo "loginctl enable-linger $ACTUAL_USER"
                echo "su - $ACTUAL_USER -c 'systemctl --user enable --now podman.socket'"
                exit 1
            fi
        fi
    fi
    
    echo "Using Podman socket at: $PODMAN_SOCKET"

    get_private_ip() {
        ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"

    echo "Updating Dokploy-Podman..."
    
    # Pull the latest image
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman pull ghcr.io/nextscholar/dokploy-podman:latest"

    # Update the container
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman stop dokploy"
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman rm dokploy"
    
    # Get Podman storage path
    PODMAN_STORAGE_PATH=$(sudo -u $ACTUAL_USER XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID podman info --format "{{.Store.GraphRoot}}")

    # Run Dokploy in the pod with proper storage access
    XDG_RUNTIME_DIR=/run/user/$ACTUAL_USER_UID su - $ACTUAL_USER -c "podman run -d \
        --pod dokploy-pod \
        --name dokploy \
        -v ${PODMAN_SOCKET}:/var/run/docker.sock:rw \
        -v ${PODMAN_STORAGE_PATH}:${PODMAN_STORAGE_PATH}:rw \
        -v ${PODMAN_SOCKET}:/var/run/podman/podman.sock:rw \
        -v /run/user/$ACTUAL_USER_UID:/run/user/$ACTUAL_USER_UID:rw \
        -v /etc/dokploy:/etc/dokploy:Z \
        -v /var/lib/dokploy:/var/lib/dokploy:Z \
        -v /etc/subuid:/etc/subuid:ro \
        -v /etc/subgid:/etc/subgid:ro \
        -v /usr/bin/podman:/usr/bin/podman:ro \
        -v /etc/containers:/etc/containers:ro \
        --security-opt seccomp=unconfined \
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
        --security-opt label=disable \
        ghcr.io/nextscholar/dokploy-podman:latest"

    echo "Dokploy-Podman has been updated to the latest version in rootless mode."
}

# Main script execution
if [ "$1" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi