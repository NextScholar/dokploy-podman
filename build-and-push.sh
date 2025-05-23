#!/bin/bash
# Script to build and push the dokploy-podman Docker image to GitHub Container Registry

# Configuration
IMAGE_NAME="dokploy-podman"
GITHUB_ORG="nextscholar"
FULL_IMAGE_NAME="ghcr.io/$GITHUB_ORG/$IMAGE_NAME:latest"

echo "===== Building Dokploy Podman Docker Image ====="

# Navigate to the right directory
cd "$(dirname "$0")"

# Build the Docker image
echo "Building Docker image: $IMAGE_NAME"
rm -rf .next
podman build --network=host --ulimit nofile=4096:4096 -t $IMAGE_NAME -f Dockerfile.podman .

if [ $? -ne 0 ]; then
  echo "❌ Error: Docker build failed."
  exit 1
fi

echo "✅ Docker image built successfully: $IMAGE_NAME:latest"

# Check if we should push the image
read -p "Push image to GitHub Container Registry? (y/n): " PUSH_CONFIRM

if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  echo "===== Pushing Image to GitHub Container Registry ====="
  
  # Check if logged in to GitHub Container Registry
  if ! podman info 2>/dev/null | grep -q "ghcr.io"; then
    echo "⚠️ Not logged in to GitHub Container Registry."
    echo "Please run: podman login ghcr.io"
    read -p "Press Enter after login to continue or Ctrl+C to cancel..." 
  fi
  
  # Tag and push image
  echo "Tagging image as: $FULL_IMAGE_NAME"
  podman tag $IMAGE_NAME $FULL_IMAGE_NAME
  
  echo "Pushing image to: $FULL_IMAGE_NAME"
  if ! podman push $FULL_IMAGE_NAME; then
    echo "❌ Error: Failed to push image to GitHub Container Registry."
    exit 1
  fi
  
  echo "✅ Successfully pushed image to GitHub Container Registry: $FULL_IMAGE_NAME"
fi

echo "===== Dokploy Podman Docker Process Complete ====="
