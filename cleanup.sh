#!/bin/bash
# Cleanup script to remove unnecessary files and keep only the essential ones

echo "===== Cleaning up unnecessary files ====="

# List of files to keep
KEEP_FILES=(
  "install-podman.sh"
  "podman-adapter.sh"
  "docker-to-podman.sh"
  "DOCKER-PODMAN-COMPATIBILITY.md"
  "README.md"
  "README-podman.md"
)

# Remove scripts that we don't need
FILES_TO_REMOVE=(
  "build-and-push.sh"
  "setup-docker-alias.sh"
  "quick-install.sh"
  "test-docker-podman.sh"
  "dokploy-cleanup.sh"
)

for file in "${FILES_TO_REMOVE[@]}"; do
  if [ -f "$file" ]; then
    echo "Removing $file"
    rm "$file"
  fi
done

echo "===== Cleanup complete ====="
echo "The following files were kept:"
for file in "${KEEP_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "- $file"
  fi
done
