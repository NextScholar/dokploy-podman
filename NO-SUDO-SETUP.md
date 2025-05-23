# Podman Without Sudo Setup

This document explains the changes made to allow Podman to run without sudo.

## Changes Made

1. **Updated `install-podman.sh`**:
   - Created a `podman` group
   - Added the current user to the `podman` group
   - Set proper permissions on the Podman socket (root:podman with 660 permissions)

2. **Updated `docker-to-podman.sh`**:
   - Set proper permissions (755) on the docker command symlink

3. **Updated `setup-docker-alias.sh`**:
   - Set proper permissions (755) on the docker command symlink
   - Added `hash -r` to the alias script to refresh command paths

## Why These Changes Were Needed

Podman is designed to be usable without root privileges, but the socket permissions need to be configured correctly:

1. **Socket Permissions**: The Podman socket needs to be accessible by non-root users in the `podman` group
2. **User Group Membership**: Users need to be in the `podman` group to access the socket
3. **Symlink Permissions**: The Docker-to-Podman symlink needs to be executable by all users

## Testing

After the changes, run:

```bash
sudo ./dokploy-cleanup.sh      # Clean up everything
sudo ./install-podman.sh       # Install Podman with proper permissions
sudo ./docker-to-podman.sh     # Set up Docker-to-Podman mapping
source /etc/profile.d/docker-podman-alias.sh  # Load the alias
./test.sh                      # Test without sudo
```

You should now be able to run Podman and Docker commands without sudo.

## Note

You might need to log out and log back in for the group membership changes to take full effect.
