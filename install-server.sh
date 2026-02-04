#!/bin/bash
# Docker Registry Proxy - Server Installation Script
# One-line install: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-server.sh | bash -s -- your-domain.com your-email@example.com
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
    if grep -r "server_name.*$DOMAIN" /etc/nginx/sites-available/ /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null; then
        log_error "Domain '$DOMAIN' is already configured in nginx!"
        log_error "Please remove the existing configuration or use a different domain."
        exit 1
    fi
fi

log_info "No existing nginx configuration found for $DOMAIN"

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
    log_info "git is already installed"
fi

# Install curl if not present
if ! command -v curl &> /dev/null; then
    log_info "Installing curl..."
    $SUDO apt-get install -y -qq curl
else
    log_info "curl is already installed"
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
    
    log_info "Docker installed successfully!"
else
    log_info "Docker is already installed"
    
    # Ensure docker compose plugin is available
    if ! docker compose version &> /dev/null; then
        log_info "Installing docker-compose-plugin..."
        $SUDO apt-get install -y -qq docker-compose-plugin
    fi
fi

# Install certbot if not present (standalone, not nginx plugin)
if ! command -v certbot &> /dev/null; then
    log_info "Installing certbot..."
    $SUDO apt-get install -y -qq certbot
else
    log_info "certbot is already installed"
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
$SUDO mkdir -p cache certs ssl certbot/www certbot/conf

# ============================================
# Configure nginx virtual host
# ============================================
log_info "Configuring nginx for $DOMAIN..."

# Update domain in nginx config
$SUDO sed -i "s/YOUR_DOMAIN_HERE/$DOMAIN/g" nginx/conf.d/default.conf 2>/dev/null || true

# ============================================
# Get SSL certificate (if not exists)
# ============================================
if [ "$EXISTING_CERTS" = false ]; then
    log_info "Obtaining SSL certificate from Let's Encrypt..."
    
    # Create temporary self-signed cert for initial nginx startup
    $SUDO mkdir -p certbot/conf/live/$DOMAIN
    $SUDO openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
        -keyout certbot/conf/live/$DOMAIN/privkey.pem \
        -out certbot/conf/live/$DOMAIN/fullchain.pem \
        -subj "/CN=$DOMAIN" 2>/dev/null

    # Start nginx temporarily for certbot challenge
    $SUDO docker compose up -d nginx
    sleep 5

    # Get real certificate
    $SUDO docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN"

    # Restart with real certificate
    $SUDO docker compose down
else
    log_info "Using existing SSL certificates for $DOMAIN"
    # Link existing certificates
    $SUDO mkdir -p certbot/conf/live
    $SUDO ln -sf /etc/letsencrypt/live/$DOMAIN certbot/conf/live/$DOMAIN 2>/dev/null || true
fi

# ============================================
# Start services
# ============================================
log_info "Starting docker-registry-proxy services..."
$SUDO docker compose up -d

# Wait for services to be ready
sleep 5

# Copy CA certificate for distribution
log_info "Extracting CA certificate..."
$SUDO docker cp docker-registry-proxy:/ca/ca.crt ./ssl/ca.crt 2>/dev/null || log_warn "CA cert will be available shortly"
$SUDO chmod 644 ssl/ca.crt 2>/dev/null || true

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
echo "  - Proxy port: $DOMAIN:3128"
echo ""
log_info "To configure Docker clients, run:"
echo ""
echo "  # Linux (Debian/Ubuntu):"
echo "  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- $DOMAIN"
echo ""
echo "  # macOS/Windows (Docker Desktop):"
echo "  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- $DOMAIN"
echo ""
log_info "Management commands:"
echo "  cd $INSTALL_DIR"
echo "  docker compose logs -f      # View logs"
echo "  docker compose restart      # Restart services"
echo "  docker compose down         # Stop services"
echo ""
