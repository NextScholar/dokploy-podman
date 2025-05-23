# Docker to Podman Compatibility

This document explains how our Docker-to-Podman compatibility layer works, both on the host system and inside containers.

## Overview

Our system uses Podman instead of Docker, but maintains full compatibility with applications that expect Docker to be installed. This is achieved through three mechanisms:

1. Host system Docker command redirection
2. Container socket mounting
3. Container-internal Docker command emulation

## Host System Compatibility

On the host system, all `docker` commands are redirected to equivalent `podman` commands via our adapter script:

- The adapter is installed at `/usr/local/bin/docker`
- A system-wide alias is set up in `/etc/profile.d/docker-podman-alias.sh`
- The adapter script handles command translation, including special cases for Docker features that don't have direct Podman equivalents

## Container Socket Compatibility

For applications that communicate with Docker via the Docker socket (e.g., using Docker API):

- The Podman socket (`/run/podman/podman.sock`) is mounted to the standard Docker socket path (`/var/run/docker.sock`) inside containers
- This enables containerized applications to use the Docker API without modification
- Applications using Docker clients/SDKs will work transparently with Podman

## Inside Container Compatibility

For Docker CLI commands executed inside containers:

- In our containers, `/usr/bin/docker` is already a wrapper script that redirects to Podman
- The script shows: `Emulate Docker CLI using podman` when executed
- This enables any Docker CLI commands inside the container to work with Podman automatically

## Limitations

- Nested containers (running Podman inside Podman) may have limitations
- Some Docker-specific features (Swarm, Services) are emulated with similar Podman features but aren't 100% compatible
- For applications that require specific Docker features, additional configuration may be needed

## Troubleshooting

If you encounter issues with Docker compatibility:

1. Check the logs at `~/.podman-adapter.log` on the host system
2. Verify that the Docker socket is properly mounted in containers
3. For container-specific issues, check if the container has the Docker-to-Podman wrapper at `/usr/bin/docker`
4. Create the file `/etc/containers/nodocker` to suppress the "Emulate Docker CLI" message if needed
