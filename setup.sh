#!/bin/bash
# Docker Registry Proxy Setup Script for Debian
# Usage: ./setup.sh your-domain.com [your-email@example.com]

set -e

DOMAIN="${1:-}"
EMAIL="${2:-admin@$DOMAIN}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if domain is provided
if [ -z "$DOMAIN" ]; then
    log_error "Usage: ./setup.sh your-domain.com [your-email@example.com]"
    exit 1
fi

log_info "Setting up Docker Registry Proxy for domain: $DOMAIN"

# Step 1: Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Installing Docker..."
    
    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    log_info "Docker installed successfully!"
else
    log_info "Docker is already installed."
fi

# Step 2: Create directory structure
log_info "Creating directory structure..."
mkdir -p cache certs ssl nginx/conf.d certbot/www certbot/conf

# Step 3: Replace domain placeholder in nginx config
log_info "Configuring Nginx for domain: $DOMAIN"
sed -i "s/YOUR_DOMAIN_HERE/$DOMAIN/g" nginx/conf.d/default.conf

# Step 4: Create initial self-signed certificate (for initial startup)
log_info "Creating temporary self-signed certificate..."
mkdir -p certbot/conf/live/$DOMAIN
openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
    -keyout certbot/conf/live/$DOMAIN/privkey.pem \
    -out certbot/conf/live/$DOMAIN/fullchain.pem \
    -subj "/CN=$DOMAIN" 2>/dev/null

# Step 5: Start services (nginx only for certbot challenge)
log_info "Starting Nginx for Let's Encrypt challenge..."
docker compose up -d nginx

# Wait for nginx to start
sleep 5

# Step 6: Get Let's Encrypt certificate
log_info "Obtaining Let's Encrypt certificate..."
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN

# Step 7: Restart nginx with real certificate
log_info "Restarting Nginx with Let's Encrypt certificate..."
docker compose down
docker compose up -d

# Step 8: Copy CA certificate for client distribution
log_info "Copying CA certificate for client distribution..."
sleep 5
docker cp docker-registry-proxy:/ca/ca.crt ./ssl/ca.crt 2>/dev/null || log_warn "CA cert not ready yet, will be available after proxy starts"

# Step 9: Set proper permissions
chmod 644 ssl/ca.crt 2>/dev/null || true

log_info "=========================================="
log_info "Setup complete!"
log_info "=========================================="
echo ""
log_info "Your Docker Registry Proxy is now running at:"
echo "  - HTTPS: https://$DOMAIN"
echo "  - Proxy port: $DOMAIN:3128"
echo ""
log_info "To configure Docker clients, run on each client:"
echo "  curl -O https://$DOMAIN/ca.crt"
echo "  sudo cp ca.crt /usr/local/share/ca-certificates/docker-proxy-ca.crt"
echo "  sudo update-ca-certificates"
echo ""
log_info "Then configure Docker to use the proxy (see client-setup.sh)"
echo ""
log_info "View logs with: docker compose logs -f"
