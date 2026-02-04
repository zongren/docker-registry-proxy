#!/bin/bash
# Docker Client Setup Script
# Run this on each Docker client that needs to use the registry proxy
# Usage: ./client-setup.sh proxy.yourdomain.com

set -e

PROXY_HOST="${1:-}"
PROXY_PORT="${2:-3128}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ -z "$PROXY_HOST" ]; then
    log_error "Usage: ./client-setup.sh proxy.yourdomain.com [proxy-port]"
    exit 1
fi

log_info "Configuring Docker to use proxy: $PROXY_HOST:$PROXY_PORT"

# Step 1: Download and install CA certificate
log_info "Downloading CA certificate from proxy server..."
curl -sSfL "https://${PROXY_HOST}/ca.crt" -o /tmp/docker-proxy-ca.crt

# Detect OS and install certificate
if [ -f /etc/debian_version ]; then
    log_info "Detected Debian/Ubuntu, installing CA certificate..."
    sudo cp /tmp/docker-proxy-ca.crt /usr/local/share/ca-certificates/docker-proxy-ca.crt
    sudo update-ca-certificates
elif [ -f /etc/redhat-release ]; then
    log_info "Detected RHEL/CentOS, installing CA certificate..."
    sudo cp /tmp/docker-proxy-ca.crt /etc/pki/ca-trust/source/anchors/docker-proxy-ca.crt
    sudo update-ca-trust
elif [[ "$OSTYPE" == "darwin"* ]]; then
    log_info "Detected macOS, installing CA certificate..."
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /tmp/docker-proxy-ca.crt
else
    log_warn "Unknown OS. Please manually install the CA certificate from /tmp/docker-proxy-ca.crt"
fi

# Step 2: Create Docker proxy configuration directory
log_info "Creating Docker proxy configuration..."
sudo mkdir -p /etc/systemd/system/docker.service.d

# Step 3: Create proxy configuration file
cat << EOF | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://${PROXY_HOST}:${PROXY_PORT}"
Environment="HTTPS_PROXY=http://${PROXY_HOST}:${PROXY_PORT}"
Environment="NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
EOF

# Step 4: Reload systemd and restart Docker
log_info "Restarting Docker daemon..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Step 5: Verify configuration
log_info "Verifying Docker proxy configuration..."
sudo systemctl show --property=Environment docker | grep -q "PROXY" && \
    log_info "Docker proxy configuration verified!" || \
    log_warn "Could not verify proxy configuration"

# Step 6: Test by pulling an image
log_info "Testing proxy by pulling hello-world image..."
if docker pull hello-world; then
    log_info "=========================================="
    log_info "Setup complete! Docker is now using the proxy."
    log_info "=========================================="
else
    log_error "Failed to pull test image. Please check the proxy server."
fi

echo ""
log_info "Configuration summary:"
echo "  Proxy server: $PROXY_HOST:$PROXY_PORT"
echo "  Config file: /etc/systemd/system/docker.service.d/http-proxy.conf"
echo ""
log_info "To verify, run: docker info | grep -i proxy"
