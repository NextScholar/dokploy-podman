#!/bin/bash
# This script provides compatibility between Docker CLI and Podman
# It intercepts all Docker commands and translates them to Podman equivalents

# Set environment variables for Podman socket
export DOCKER_HOST="unix:///var/run/podman/podman.sock"
export CONTAINER_HOST="unix:///var/run/podman/podman.sock"

# Use a user-accessible log file
LOG_FILE="${HOME}/.podman-adapter.log"
touch $LOG_FILE 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE 2>/dev/null || true
}

log "Command received: $0 $@"

# Special case: If docker itself is called without any arguments, show podman help
if [ "$#" -eq 0 ]; then
  podman --help
  exit $?
fi

# Handle docker-compose to podman-compose conversion
if [[ "$1" == "compose" ]]; then
  shift
  if command -v podman-compose >/dev/null 2>&1; then
    log "Executing: podman-compose $@"
    podman-compose "$@"
  else
    echo "Warning: podman-compose not found. Attempting to use podman with compose subcommand."
    log "Executing fallback: podman compose $@"
    podman compose "$@"
  fi
  exit $?
fi

# Handle docker swarm commands (limited support)
if [[ "$1" == "swarm" ]]; then
  echo "Docker Swarm features are not fully supported in Podman."
  if [[ "$2" == "init" ]]; then
    echo "Creating a pod as an alternative to swarm..."
    log "Executing pod create instead of swarm init"
    podman pod create --name dokploy-pod
    exit $?
  elif [[ "$2" == "leave" || "$2" == "rm" ]]; then
    echo "Removing the pod as an alternative to leaving swarm..."
    log "Executing pod rm instead of swarm leave"
    podman pod rm -f dokploy-pod 2>/dev/null || true
    exit $?
  else
    echo "This swarm command doesn't have a direct Podman equivalent."
    exit 1
  fi
fi

# Handle docker service commands (limited support)
if [[ "$1" == "service" ]]; then
  echo "Docker Service features are not fully supported in Podman."
  
  if [[ "$2" == "create" || "$2" == "run" ]]; then
    echo "Consider using 'podman run' as an alternative."
    # A very simple conversion might look like this
    # This is incomplete and would need enhancement for real use
    shift 2
    log "Converting service create/run to podman run"
    podman run -d "$@"
    exit $?
  elif [[ "$2" == "ls" || "$2" == "list" ]]; then
    echo "Listing all containers instead of services..."
    log "Converting service ls to podman ps"
    podman ps
    exit $?
  elif [[ "$2" == "rm" ]]; then
    shift 2
    echo "Removing container instead of service..."
    log "Converting service rm to podman rm"
    podman rm "$@"
    exit $?
  else
    echo "This service command doesn't have a direct Podman equivalent."
    exit 1
  fi
fi

# Handle docker stack commands
if [[ "$1" == "stack" ]]; then
  echo "Docker Stack features are not fully supported in Podman."
  echo "Consider using 'podman-compose' or 'podman pod' as alternatives."
  exit 1
fi

# Handle docker network commands
if [[ "$1" == "network" ]]; then
  # These commands work the same in podman
  log "Passing network command directly to podman: podman network $@"
  podman network "${@:2}"
  exit $?
fi

# Handle docker volume commands
if [[ "$1" == "volume" ]]; then
  # These commands work the same in podman
  log "Passing volume command directly to podman: podman volume $@"
  podman volume "${@:2}"
  exit $?
fi

# Handle docker system commands
if [[ "$1" == "system" ]]; then
  # These commands work the same in podman
  log "Passing system command directly to podman: podman system $@"
  podman system "${@:2}"
  exit $?
fi

# For all other commands, pass through to podman
log "Executing: podman $@"
podman "$@"
exit $?
