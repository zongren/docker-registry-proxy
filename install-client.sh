#!/bin/bash
# Docker Registry Proxy - Client Installation Script
# Supports: Debian 12, macOS (Docker Desktop), Windows (Docker Desktop via Git Bash/WSL)
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.sh | bash -s -- proxy.example.com
#
# Requirements:
# - Docker must be already installed (Docker Engine on Linux, Docker Desktop on macOS/Windows)
# - This script will NOT install Docker - it will exit with an error if Docker is not found
#
# On Windows, run this script in:
# - Git Bash, or
# - WSL (Windows Subsystem for Linux), or
# - PowerShell with bash available

set -e

PROXY_HOST="${1:-}"
PROXY_PORT="${2:-3128}"

# Colors (may not work in all Windows terminals)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)
            if [ -f /etc/debian_version ]; then
                OS="debian"
            elif [ -f /etc/redhat-release ]; then
                OS="rhel"
            else
                OS="linux"
            fi
            ;;
        Darwin*)
            OS="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="windows"
            ;;
        *)
            OS="unknown"
            ;;
    esac
    echo "$OS"
}

# Validate arguments
if [ -z "$PROXY_HOST" ]; then
    log_error "Usage: $0 <proxy-host> [proxy-port]"
    log_error "Example: $0 proxy.example.com 3128"
    exit 1
fi

OS=$(detect_os)
log_info "=========================================="
log_info "Docker Registry Proxy - Client Installer"
log_info "=========================================="
log_info "Proxy: $PROXY_HOST:$PROXY_PORT"
log_info "Detected OS: $OS"
echo ""

# ============================================
# Check if Docker is installed
# ============================================
log_info "Checking for Docker installation..."

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed!"
    echo ""
    case "$OS" in
        debian|linux)
            log_error "Please install Docker Engine first:"
            log_error "  https://docs.docker.com/engine/install/debian/"
            ;;
        macos)
            log_error "Please install Docker Desktop for Mac first:"
            log_error "  https://docs.docker.com/desktop/install/mac-install/"
            ;;
        windows)
            log_error "Please install Docker Desktop for Windows first:"
            log_error "  https://docs.docker.com/desktop/install/windows-install/"
            ;;
        *)
            log_error "Please install Docker first: https://docs.docker.com/get-docker/"
            ;;
    esac
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running!"
    case "$OS" in
        macos|windows)
            log_error "Please start Docker Desktop and try again."
            ;;
        *)
            log_error "Please start the Docker service: sudo systemctl start docker"
            ;;
    esac
    exit 1
fi

log_info "Docker is installed and running"

# ============================================
# Download CA certificate
# ============================================
log_info "Downloading CA certificate from proxy server..."

CA_CERT_URL="https://${PROXY_HOST}/ca.crt"
TEMP_CA_CERT="/tmp/docker-proxy-ca.crt"

# Try to download the CA cert
if ! curl -sSfL "$CA_CERT_URL" -o "$TEMP_CA_CERT" 2>/dev/null; then
    # Try with -k for self-signed cert on the proxy
    if ! curl -sSfLk "$CA_CERT_URL" -o "$TEMP_CA_CERT" 2>/dev/null; then
        log_error "Failed to download CA certificate from $CA_CERT_URL"
        log_error "Please ensure the proxy server is running and accessible."
        exit 1
    fi
fi

log_info "CA certificate downloaded"

# ============================================
# Install CA certificate (OS-specific)
# ============================================
log_info "Installing CA certificate..."

case "$OS" in
    debian)
        if [ "$EUID" -ne 0 ]; then
            SUDO="sudo"
        else
            SUDO=""
        fi
        $SUDO cp "$TEMP_CA_CERT" /usr/local/share/ca-certificates/docker-proxy-ca.crt
        $SUDO update-ca-certificates
        log_info "CA certificate installed to system trust store"
        ;;
        
    rhel)
        if [ "$EUID" -ne 0 ]; then
            SUDO="sudo"
        else
            SUDO=""
        fi
        $SUDO cp "$TEMP_CA_CERT" /etc/pki/ca-trust/source/anchors/docker-proxy-ca.crt
        $SUDO update-ca-trust
        log_info "CA certificate installed to system trust store"
        ;;
        
    macos)
        log_info "Installing CA certificate to macOS Keychain..."
        log_warn "You may be prompted for your password"
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$TEMP_CA_CERT" 2>/dev/null || {
            log_warn "Failed to add to System keychain, trying user keychain..."
            security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db "$TEMP_CA_CERT" || {
                log_error "Failed to install CA certificate"
                log_error "Please manually add $TEMP_CA_CERT to Keychain Access"
                exit 1
            }
        }
        log_info "CA certificate installed to Keychain"
        ;;
        
    windows)
        log_warn "Windows detected. Please install the CA certificate manually:"
        echo ""
        echo "  1. Open the certificate file: $TEMP_CA_CERT"
        echo "  2. Double-click to open Certificate Import Wizard"
        echo "  3. Select 'Local Machine' and click Next"
        echo "  4. Select 'Place all certificates in the following store'"
        echo "  5. Browse and select 'Trusted Root Certification Authorities'"
        echo "  6. Click Next and Finish"
        echo ""
        log_warn "Alternatively, run in PowerShell as Administrator:"
        echo "  Import-Certificate -FilePath \"$TEMP_CA_CERT\" -CertStoreLocation Cert:\\LocalMachine\\Root"
        echo ""
        ;;
        
    *)
        log_warn "Please manually install the CA certificate: $TEMP_CA_CERT"
        ;;
esac

# ============================================
# Configure Docker to use proxy
# ============================================
log_info "Configuring Docker to use the proxy..."

case "$OS" in
    debian|linux|rhel)
        # Linux with systemd
        if [ "$EUID" -ne 0 ]; then
            SUDO="sudo"
        else
            SUDO=""
        fi
        
        $SUDO mkdir -p /etc/systemd/system/docker.service.d
        
        cat << EOF | $SUDO tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
[Service]
Environment="HTTP_PROXY=http://${PROXY_HOST}:${PROXY_PORT}"
Environment="HTTPS_PROXY=http://${PROXY_HOST}:${PROXY_PORT}"
Environment="NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
EOF
        
        log_info "Restarting Docker daemon..."
        $SUDO systemctl daemon-reload
        $SUDO systemctl restart docker
        log_info "Docker daemon restarted with proxy configuration"
        ;;
        
    macos)
        log_info "Configuring Docker Desktop for macOS..."
        
        # Docker Desktop on macOS needs configuration in multiple places:
        # 1. ~/.docker/daemon.json for the Docker daemon
        # 2. The Docker Desktop settings.json for the GUI
        
        DOCKER_CONFIG_DIR="$HOME/.docker"
        DAEMON_CONFIG="$DOCKER_CONFIG_DIR/daemon.json"
        
        mkdir -p "$DOCKER_CONFIG_DIR"
        
        # Configure daemon.json with proxy settings
        log_info "Configuring Docker daemon proxy settings..."
        
        if [ -f "$DAEMON_CONFIG" ]; then
            cp "$DAEMON_CONFIG" "$DAEMON_CONFIG.backup"
            log_info "Backed up existing daemon.json to $DAEMON_CONFIG.backup"
            
            # Use Python to merge proxy settings into existing config
            python3 << PYEOF
import json
import os

config_path = "$DAEMON_CONFIG"
try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except:
    config = {}

# Add proxy settings (these work for Docker daemon)
config['proxies'] = {
    'http-proxy': 'http://${PROXY_HOST}:${PROXY_PORT}',
    'https-proxy': 'http://${PROXY_HOST}:${PROXY_PORT}',
    'no-proxy': 'localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local'
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("Updated", config_path)
PYEOF
        else
            cat << EOF > "$DAEMON_CONFIG"
{
  "proxies": {
    "http-proxy": "http://${PROXY_HOST}:${PROXY_PORT}",
    "https-proxy": "http://${PROXY_HOST}:${PROXY_PORT}",
    "no-proxy": "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
  }
}
EOF
            log_info "Created $DAEMON_CONFIG with proxy settings"
        fi
        
        # Also configure ~/.docker/config.json for container proxy settings
        DOCKER_CONFIG="$DOCKER_CONFIG_DIR/config.json"
        if [ -f "$DOCKER_CONFIG" ]; then
            cp "$DOCKER_CONFIG" "$DOCKER_CONFIG.backup.config"
            python3 << PYEOF
import json
import os

config_path = "$DOCKER_CONFIG"
try:
    with open(config_path, 'r') as f:
        config = json.load(f)
except:
    config = {}

config['proxies'] = {
    'default': {
        'httpProxy': 'http://${PROXY_HOST}:${PROXY_PORT}',
        'httpsProxy': 'http://${PROXY_HOST}:${PROXY_PORT}',
        'noProxy': 'localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local'
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("Updated", config_path)
PYEOF
        else
            cat << EOF > "$DOCKER_CONFIG"
{
  "proxies": {
    "default": {
      "httpProxy": "http://${PROXY_HOST}:${PROXY_PORT}",
      "httpsProxy": "http://${PROXY_HOST}:${PROXY_PORT}",
      "noProxy": "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
    }
  }
}
EOF
            log_info "Created $DOCKER_CONFIG with proxy settings"
        fi
        
        log_info "Proxy configuration files updated"
        
        echo ""
        log_warn "==========================================="
        log_warn "IMPORTANT: Manual steps required!"
        log_warn "==========================================="
        echo ""
        echo "Docker Desktop on macOS requires manual proxy configuration:"
        echo ""
        echo "  1. Click the Docker icon in the menu bar"
        echo "  2. Select 'Settings' (or 'Preferences')"
        echo "  3. Go to 'Resources' → 'Proxies'"
        echo "  4. Enable 'Manual proxy configuration'"
        echo "  5. Set HTTP Proxy:  http://${PROXY_HOST}:${PROXY_PORT}"
        echo "  6. Set HTTPS Proxy: http://${PROXY_HOST}:${PROXY_PORT}"
        echo "  7. Set Bypass: localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
        echo "  8. Click 'Apply & Restart'"
        echo ""
        log_info "After configuring, test with: docker pull nginx:alpine"
        echo ""
        ;;
        
    windows)
        log_info "Configuring Docker Desktop for Windows..."
        
        # Docker Desktop on Windows uses %USERPROFILE%\.docker\config.json
        DOCKER_CONFIG_DIR="$HOME/.docker"
        DOCKER_CONFIG="$DOCKER_CONFIG_DIR/config.json"
        
        mkdir -p "$DOCKER_CONFIG_DIR"
        
        if [ -f "$DOCKER_CONFIG" ]; then
            cp "$DOCKER_CONFIG" "$DOCKER_CONFIG.backup"
            log_info "Backed up existing config"
        fi
        
        # Create/update config
        cat << EOF > "$DOCKER_CONFIG"
{
  "proxies": {
    "default": {
      "httpProxy": "http://${PROXY_HOST}:${PROXY_PORT}",
      "httpsProxy": "http://${PROXY_HOST}:${PROXY_PORT}",
      "noProxy": "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
    }
  }
}
EOF
        
        log_info "Docker config updated with proxy settings"
        echo ""
        log_warn "Please restart Docker Desktop for changes to take effect:"
        echo "  1. Right-click the Docker icon in the system tray"
        echo "  2. Select 'Restart'"
        echo ""
        ;;
esac

# ============================================
# Test the configuration
# ============================================
echo ""
log_info "Testing Docker proxy configuration..."

# Give Docker a moment to restart (on Linux)
if [ "$OS" = "debian" ] || [ "$OS" = "linux" ] || [ "$OS" = "rhel" ]; then
    sleep 3
fi

if docker pull hello-world &> /dev/null; then
    docker rmi hello-world &> /dev/null || true
    log_info "=========================================="
    log_info "Setup Complete!"
    log_info "=========================================="
    echo ""
    log_info "Docker is now configured to use the proxy at $PROXY_HOST:$PROXY_PORT"
    echo ""
    log_info "Test by pulling an image:"
    echo "  docker pull nginx:latest"
    echo ""
else
    if [ "$OS" = "macos" ] || [ "$OS" = "windows" ]; then
        log_warn "Please restart Docker Desktop and then test with:"
        echo "  docker pull hello-world"
    else
        log_warn "Test pull failed. This might be expected if Docker is still restarting."
        echo "Try manually: docker pull hello-world"
    fi
fi

# ============================================
# Verify configuration
# ============================================
echo ""
log_info "To verify proxy configuration:"
case "$OS" in
    debian|linux|rhel)
        echo "  docker info | grep -i proxy"
        ;;
    macos|windows)
        echo "  cat ~/.docker/config.json"
        ;;
esac

# Cleanup
rm -f "$TEMP_CA_CERT" 2>/dev/null || true
