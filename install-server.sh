#!/bin/bash
# Docker Registry Proxy - Server Installation Script (for servers with existing nginx)
# One-line install: curl -fsSL https://raw.githubusercontent.com/zongren/docker-registry-proxy/main/install-server.sh | bash -s -- your-domain.com your-email@example.com
#
# Requirements:
# - Debian 12 (bookworm)
# - Root or sudo access
# - Domain pointing to this server's IP
# - Ports 80, 443, 3128 open
#
# This script will:
# - Install git, docker, certbot if not present
# - Check if nginx site already exists (exit with error if so)
# - NOT modify existing nginx configurations or certificates
# - Add a new nginx site for the proxy domain
# - Deploy the docker-registry-proxy

set -e

# Configuration
DOMAIN="${1:-}"
EMAIL="${2:-admin@$DOMAIN}"
REPO_URL="https://github.com/zongren/docker-registry-proxy.git"
INSTALL_DIR="/opt/docker-registry-proxy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root or with sudo
check_root() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            log_error "This script requires root privileges. Please run as root or install sudo."
            exit 1
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Validate arguments
if [ -z "$DOMAIN" ]; then
    log_error "Usage: $0 <domain> [email]"
    log_error "Example: $0 proxy.example.com admin@example.com"
    exit 1
fi

log_info "=========================================="
log_info "Docker Registry Proxy - Server Installer"
log_info "=========================================="
log_info "Domain: $DOMAIN"
log_info "Email: $EMAIL"
echo ""

check_root

# Check OS
if [ ! -f /etc/debian_version ]; then
    log_error "This script only supports Debian-based systems."
    exit 1
fi

DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
log_info "Detected Debian version: $DEBIAN_VERSION"

# ============================================
# Check if nginx site already exists
# ============================================
log_info "Checking for existing nginx configuration..."

if [ -f "/etc/nginx/sites-available/$DOMAIN" ] || [ -f "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    log_error "Nginx site configuration for '$DOMAIN' already exists!"
    log_error "Found in: /etc/nginx/sites-available/ or /etc/nginx/sites-enabled/"
    log_error "Please remove the existing configuration or use a different domain."
    exit 1
fi

# Check if domain is configured in any nginx config
if command -v nginx &> /dev/null; then
    if grep -r "server_name.*[[:space:]]$DOMAIN" /etc/nginx/sites-available/ /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | grep -v "^#"; then
        log_error "Domain '$DOMAIN' is already configured in nginx!"
        log_error "Please remove the existing configuration or use a different domain."
        exit 1
    fi
fi

log_info "No existing nginx configuration found for $DOMAIN ✓"

# ============================================
# Check for existing SSL certificates
# ============================================
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    log_warn "SSL certificates already exist for $DOMAIN"
    log_warn "Will reuse existing certificates (not modifying them)"
    EXISTING_CERTS=true
else
    EXISTING_CERTS=false
fi

# ============================================
# Install dependencies
# ============================================
log_info "Updating package lists..."
$SUDO apt-get update -qq

# Install git if not present
if ! command -v git &> /dev/null; then
    log_info "Installing git..."
    $SUDO apt-get install -y -qq git
else
    log_info "git is already installed ✓"
fi

# Install curl if not present
if ! command -v curl &> /dev/null; then
    log_info "Installing curl..."
    $SUDO apt-get install -y -qq curl
else
    log_info "curl is already installed ✓"
fi

# Install nginx if not present
if ! command -v nginx &> /dev/null; then
    log_info "Installing nginx..."
    $SUDO apt-get install -y -qq nginx
    $SUDO systemctl enable nginx
    $SUDO systemctl start nginx
else
    log_info "nginx is already installed ✓"
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    log_info "Installing Docker..."
    
    # Install prerequisites
    $SUDO apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true

    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start and enable Docker
    $SUDO systemctl start docker
    $SUDO systemctl enable docker
    
    log_info "Docker installed successfully ✓"
else
    log_info "Docker is already installed ✓"
    
    # Ensure docker compose plugin is available
    if ! docker compose version &> /dev/null; then
        log_info "Installing docker-compose-plugin..."
        $SUDO apt-get install -y -qq docker-compose-plugin
    fi
fi

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    log_info "Installing certbot..."
    $SUDO apt-get install -y -qq certbot python3-certbot-nginx
else
    log_info "certbot is already installed ✓"
fi

# ============================================
# Clone repository
# ============================================
log_info "Setting up docker-registry-proxy..."

if [ -d "$INSTALL_DIR" ]; then
    log_warn "Installation directory exists, updating..."
    cd "$INSTALL_DIR"
    $SUDO git pull --quiet || true
else
    log_info "Cloning repository..."
    $SUDO git clone --quiet "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# ============================================
# Create directory structure
# ============================================
log_info "Creating directory structure..."
$SUDO mkdir -p cache certs ssl

# ============================================
# Start docker-registry-proxy container
# ============================================
log_info "Starting docker-registry-proxy container..."
$SUDO docker compose up -d

# Wait for container to be ready
log_info "Waiting for container to initialize..."
sleep 5

# Copy CA certificate for distribution
log_info "Extracting CA certificate..."
$SUDO docker cp docker-registry-proxy:/ca/ca.crt ./ssl/ca.crt 2>/dev/null || {
    log_warn "CA cert not ready yet, retrying..."
    sleep 5
    $SUDO docker cp docker-registry-proxy:/ca/ca.crt ./ssl/ca.crt 2>/dev/null || log_error "Failed to extract CA cert"
}
$SUDO chmod 644 ssl/ca.crt 2>/dev/null || true

# ============================================
# Configure nginx site
# ============================================
log_info "Configuring nginx site for $DOMAIN..."

# Create nginx site config from template
$SUDO cp nginx-site.conf /etc/nginx/sites-available/$DOMAIN
$SUDO sed -i "s/YOUR_DOMAIN_HERE/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN

# For certbot to work, we need a temporary config without SSL first
$SUDO cat > /etc/nginx/sites-available/$DOMAIN << EOF
# Temporary config for certbot - will be replaced after certificate is obtained
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 200 'Waiting for SSL certificate...\n';
        add_header Content-Type text/plain;
    }
}
EOF

# Enable the site
$SUDO ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN

# Test and reload nginx
$SUDO nginx -t
$SUDO systemctl reload nginx

# ============================================
# Get SSL certificate (if not exists)
# ============================================
if [ "$EXISTING_CERTS" = false ]; then
    log_info "Obtaining SSL certificate from Let's Encrypt..."
    
    $SUDO certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domains "$DOMAIN" \
        --redirect
else
    log_info "Using existing SSL certificates for $DOMAIN"
fi

# ============================================
# Create final nginx config with SSL
# ============================================
log_info "Applying final nginx configuration..."

$SUDO cat > /etc/nginx/sites-available/$DOMAIN << EOF
# Docker Registry Proxy - $DOMAIN
# Generated by install-server.sh

# HTTP server - redirect to HTTPS and Let's Encrypt challenge
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server - main proxy endpoint
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL certificates (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Status page
    location /status {
        return 200 'Docker Registry Proxy is running\n';
        add_header Content-Type text/plain;
    }

    # Health check
    location /health {
        return 200 'OK\n';
        add_header Content-Type text/plain;
    }

    # CA certificate download (for clients to trust)
    location /ca.crt {
        alias $INSTALL_DIR/ssl/ca.crt;
        add_header Content-Type application/x-x509-ca-cert;
    }

    # Client setup script download
    location /install-client.sh {
        alias $INSTALL_DIR/install-client.sh;
        add_header Content-Type text/plain;
    }

    # PowerShell client setup script
    location /install-client.ps1 {
        alias $INSTALL_DIR/install-client.ps1;
        add_header Content-Type text/plain;
    }

    # Proxy to docker-registry-proxy container
    location / {
        proxy_pass http://127.0.0.1:3128;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # For large Docker images
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Disable buffering for streaming
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 0;
    }
}
EOF

# Test and reload nginx
$SUDO nginx -t
$SUDO systemctl reload nginx

# ============================================
# Verify services are running
# ============================================
log_info "Verifying services..."

# Check docker container
if docker ps | grep -q "docker-registry-proxy"; then
    log_info "Docker container is running ✓"
else
    log_error "Docker container is NOT running!"
    docker compose logs
    exit 1
fi

# Check nginx
if systemctl is-active --quiet nginx; then
    log_info "Nginx is running ✓"
else
    log_error "Nginx is NOT running!"
    exit 1
fi

# Test HTTPS endpoint
sleep 2
if curl -sSf "https://$DOMAIN/health" &>/dev/null; then
    log_info "HTTPS endpoint is accessible ✓"
else
    log_warn "HTTPS endpoint test failed (may need DNS propagation)"
fi

# ============================================
# Setup complete
# ============================================
echo ""
log_info "=========================================="
log_info "Installation Complete!"
log_info "=========================================="
echo ""
log_info "Docker Registry Proxy is now running at:"
echo "  - HTTPS: https://$DOMAIN"
echo "  - Proxy port: $DOMAIN:3128 (via nginx)"
echo ""
log_info "To configure Docker clients, run:"
echo ""
echo "  # Linux (Debian/Ubuntu):"
echo "  curl -fsSL https://$DOMAIN/install-client.sh | bash -s -- $DOMAIN"
echo ""
echo "  # macOS:"
echo "  curl -fsSL https://$DOMAIN/install-client.sh | bash -s -- $DOMAIN"
echo ""
echo "  # Windows PowerShell (as Administrator):"
echo '  $env:PROXY_HOST="'$DOMAIN'"; irm https://'$DOMAIN'/install-client.ps1 | iex'
echo ""
log_info "Management commands:"
echo "  cd $INSTALL_DIR"
echo "  docker compose logs -f      # View container logs"
echo "  docker compose restart      # Restart container"
echo "  docker compose down         # Stop container"
echo "  sudo systemctl reload nginx # Reload nginx"
echo ""
log_info "Nginx site config: /etc/nginx/sites-available/$DOMAIN"
echo ""
