# Dokploy Podman

This is a Podman-compatible fork of Dokploy, a free, self-hostable Platform as a Service (PaaS) that simplifies the deployment and management of applications and databases.

## 🚀 Getting Started with Podman

To get started with Dokploy using Podman, run the following command on your server:

```bash
# Full installation
sudo ./install-podman.sh

# Or simplified installation
sudo ./quick-install.sh
```

## Image Information

We maintain a custom Podman-compatible Dokploy image on GitHub Container Registry:

```
ghcr.io/nextscholar/dokploy-podman:latest
```

To build and push this image yourself:

```bash
./build-and-push.sh
```

## Features

Dokploy Podman includes the same features as the original Dokploy:

- **Applications**: Deploy any type of application (Node.js, PHP, Python, Go, Ruby, etc.).
- **Databases**: Create and manage databases with support for MySQL, PostgreSQL, MongoDB, MariaDB, and Redis.
- **Backups**: Automate backups for databases to an external storage destination.
- **Docker Compose**: Native support for Docker Compose to manage complex applications.
- **Templates**: Deploy open-source templates (Plausible, Pocketbase, Calcom, etc.) with a single click.
- **Traefik Integration**: Automatically integrates with Traefik for routing and load balancing.
- **Real-time Monitoring**: Monitor CPU, memory, storage, and network usage for every resource.
- **Docker-to-Podman Mapping**: Automatically maps Docker commands to Podman equivalents, allowing Docker-based code to run without modifications.

## Docker-to-Podman Compatibility

This fork includes a special adapter that maps Docker commands to Podman equivalents. This allows you to:

- Run code that calls Docker commands without modifications
- Use the `docker` command even when Docker is not installed
- Automatically translate Docker-specific commands to Podman alternatives
- Run applications that use the Docker API with Podman through socket redirection
- Run containerized applications that expect Docker inside Podman containers

For detailed information on how this compatibility layer works, see [DOCKER-PODMAN-COMPATIBILITY.md](./DOCKER-PODMAN-COMPATIBILITY.md).

If you need to set up the Docker-to-Podman mapping manually, you can run:

```bash
sudo ./docker-to-podman.sh
```

This is particularly useful if you encounter errors like "docker: command not found" in applications that expect Docker to be installed.

## Podman vs Docker

This fork uses Podman instead of Docker. Here are some key differences:

- Podman is daemonless (no background service required)
- Podman can run containers without root privileges
- Podman has a compatible CLI with Docker, meaning most Docker commands will work with Podman
- Podman uses pods to group containers (similar to Kubernetes pods)

## Building the Dokploy Podman Image

To build the Dokploy Podman image locally:

```bash
./build-and-push.sh
```

This will build the image and optionally push it to GitHub Container Registry.

## Updating Dokploy Podman

To update an existing installation:

```bash
curl -sSL https://raw.githubusercontent.com/NextScholar/dokploy-podman/main/install-podman.sh | sudo bash -s update
```

## Troubleshooting

If you encounter any issues:

1. Check the logs: `podman logs dokploy`
2. Verify the containers are running: `podman ps`
3. Check the Traefik logs: `podman logs dokploy-traefik`

## Credits

This project is a fork of [Dokploy](https://github.com/dokploy/dokploy), modified to work with Podman instead of Docker.
