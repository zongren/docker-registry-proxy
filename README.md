# Docker Registry Proxy

A self-hosted Docker image caching proxy that supports multiple registries (Docker Hub, GHCR, MCR, GCR, Quay.io) with SSL/TLS encryption.

## Features

- 🐳 Proxies and caches images from multiple registries
- 🔒 SSL/TLS with automatic Let's Encrypt certificates
- 🚀 Reduces bandwidth and speeds up image pulls
- 📦 Supports Docker Hub, GitHub Container Registry, Microsoft Container Registry, Google Container Registry, and Quay.io
- 🔧 One-line install for server and clients

## One-Line Install

### Server (Debian 12)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-server.sh | bash -s -- your-domain.com your-email@example.com
```

This will automatically:
- Install git, Docker, and certbot if not present
- Check for nginx conflicts (exits if domain already configured)
- Preserve existing nginx sites and SSL certificates
- Deploy the registry proxy with Let's Encrypt SSL

### Client (Debian 12 / Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- your-domain.com
```

### Client (macOS with Docker Desktop)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- your-domain.com
```

### Client (Windows with Docker Desktop)

**PowerShell (Run as Administrator):**
```powershell
$env:PROXY_HOST="your-domain.com"; irm https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.ps1 | iex
```

**Or using Git Bash / WSL:**
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- your-domain.com
```

## Prerequisites

### Server
- Debian 12 (bookworm) with root/sudo access
- Domain name pointing to your server's IP
- Ports 80, 443, and 3128 open in firewall

### Client
- Docker must already be installed:
  - **Linux**: Docker Engine
  - **macOS/Windows**: Docker Desktop
- The client scripts **will not** install Docker - they exit with an error if Docker is missing

## Manual Installation

### Server Setup

1. Clone this repository:
```bash
git clone https://github.com/YOUR_USERNAME/docker-registry-proxy.git
cd docker-registry-proxy
```

2. Run the setup script:
```bash
chmod +x setup.sh
./setup.sh your-domain.com your-email@example.com
```

### Client Setup

See [client-setup.sh](client-setup.sh) for manual configuration steps.

## Configuration

### Environment Variables

Edit `docker-compose.yml` to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `REGISTRIES` | Space-separated list of registries to proxy | `registry-1.docker.io ghcr.io mcr.microsoft.com gcr.io quay.io` |
| `HTTP_PROXY` | Upstream HTTP proxy (optional) | - |
| `HTTPS_PROXY` | Upstream HTTPS proxy (optional) | - |
| `DEBUG` | Enable debug logging | `false` |
| `CACHE_MAX_SIZE` | Maximum cache size | `100g` |

### Adding More Registries

```yaml
environment:
  - REGISTRIES=registry-1.docker.io ghcr.io mcr.microsoft.com gcr.io quay.io your-registry.com
```

### Using an Upstream Proxy

If your server needs an HTTP proxy to reach the internet:

```yaml
environment:
  - HTTP_PROXY=http://your-proxy:8080
  - HTTPS_PROXY=http://your-proxy:8080
```

## Commands

```bash
# Start services
docker compose up -d

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f docker-registry-proxy

# Restart services
docker compose restart

# Stop services
docker compose down

# Check cache size
du -sh cache/
```

## Architecture

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────┐
│  Docker Client  │────▶│   Your Server       │────▶│  Docker Hub     │
│   (anywhere)    │     │                     │     │  GHCR / MCR     │
└─────────────────┘     │  ┌───────────────┐  │     └─────────────────┘
                        │  │    Nginx      │  │
       HTTPS:443        │  │  (SSL/TLS)    │  │
       TCP:3128         │  └───────┬───────┘  │
                        │          │          │
                        │  ┌───────▼───────┐  │
                        │  │ Registry Proxy│  │
                        │  │   (Cache)     │  │
                        │  └───────────────┘  │
                        └─────────────────────┘
```

## Troubleshooting

### Certificate Issues

```bash
# Regenerate Let's Encrypt certificate
docker compose run --rm certbot certonly --force-renewal \
    --webroot --webroot-path=/var/www/certbot \
    -d your-domain.com

docker compose restart nginx
```

### Cache Issues

```bash
docker compose down
sudo rm -rf cache/*
docker compose up -d
```

### Client Can't Connect

1. Verify the proxy is running: `curl https://your-domain.com/health`
2. Check if CA cert is installed: `curl -v https://your-domain.com/ca.crt`
3. On Linux, verify Docker proxy: `docker info | grep -i proxy`

## Security Considerations

- The proxy generates its own CA certificate for MITM interception
- Clients must trust this CA certificate
- Keep the CA private key secure (stored in `./certs/`)
- Consider firewall rules to restrict access to port 3128

## License

MIT
