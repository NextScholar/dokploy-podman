#!/bin/bash
# Simple test for Docker-to-Podman mapping

echo "===== Testing Docker-to-Podman Mapping ====="

# Run a simple docker version command
echo -n "Docker version: "
docker --version

# Run docker ps to list containers
echo -n "Docker ps: "
docker ps | wc -l
echo "containers found"

# Run docker images to list images
echo -n "Docker images: "
docker images | wc -l
echo "images found"

echo ""
echo "If you see output from these commands without errors,"
echo "the Docker-to-Podman mapping is working correctly."
