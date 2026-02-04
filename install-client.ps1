# Docker Registry Proxy - Client Installation Script for Windows PowerShell
# One-line install (run as Administrator):
#   irm https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.ps1 | iex
#
# Or with parameters:
#   $env:PROXY_HOST="proxy.example.com"; $env:PROXY_PORT="3128"; irm https://raw.githubusercontent.com/YOUR_USERNAME/docker-registry-proxy/main/install-client.ps1 | iex
#
# Requirements:
# - Windows 10/11 with Docker Desktop installed
# - PowerShell running as Administrator
# - Docker Desktop must be installed (this script will NOT install it)

param(
    [string]$ProxyHost = $env:PROXY_HOST,
    [string]$ProxyPort = $(if ($env:PROXY_PORT) { $env:PROXY_PORT } else { "3128" })
)

$ErrorActionPreference = "Stop"

function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check for proxy host parameter
if (-not $ProxyHost) {
    Write-Err "Usage: .\install-client.ps1 -ProxyHost proxy.example.com [-ProxyPort 3128]"
    Write-Err ""
    Write-Err "Or set environment variables:"
    Write-Err '  $env:PROXY_HOST = "proxy.example.com"'
    Write-Err '  $env:PROXY_PORT = "3128"  # optional, defaults to 3128'
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Docker Registry Proxy - Client Installer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Info "Proxy: ${ProxyHost}:${ProxyPort}"
Write-Host ""

# ============================================
# Check if running as Administrator
# ============================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Err "This script requires Administrator privileges."
    Write-Err "Please run PowerShell as Administrator and try again."
    exit 1
}

# ============================================
# Check if Docker is installed
# ============================================
Write-Info "Checking for Docker installation..."

try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    if (-not $dockerVersion) {
        throw "Docker not responding"
    }
    Write-Info "Docker is installed (version: $dockerVersion)"
} catch {
    Write-Err "Docker is not installed or not running!"
    Write-Host ""
    Write-Err "Please install Docker Desktop for Windows first:"
    Write-Err "  https://docs.docker.com/desktop/install/windows-install/"
    Write-Host ""
    Write-Err "After installation, ensure Docker Desktop is running and try again."
    exit 1
}

# ============================================
# Download CA certificate
# ============================================
Write-Info "Downloading CA certificate from proxy server..."

$caCertUrl = "https://${ProxyHost}/ca.crt"
$tempCaCert = "$env:TEMP\docker-proxy-ca.crt"

try {
    # Try with certificate validation first
    Invoke-WebRequest -Uri $caCertUrl -OutFile $tempCaCert -UseBasicParsing
} catch {
    try {
        # Try without certificate validation (for self-signed certs)
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        Invoke-WebRequest -Uri $caCertUrl -OutFile $tempCaCert -UseBasicParsing
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
    } catch {
        Write-Err "Failed to download CA certificate from $caCertUrl"
        Write-Err "Please ensure the proxy server is running and accessible."
        exit 1
    }
}

Write-Info "CA certificate downloaded to $tempCaCert"

# ============================================
# Install CA certificate to Windows trust store
# ============================================
Write-Info "Installing CA certificate to Windows trust store..."

try {
    Import-Certificate -FilePath $tempCaCert -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Info "CA certificate installed to Trusted Root Certification Authorities"
} catch {
    Write-Err "Failed to install CA certificate: $_"
    Write-Err "Please try manually importing $tempCaCert"
    exit 1
}

# ============================================
# Configure Docker to use proxy
# ============================================
Write-Info "Configuring Docker to use the proxy..."

$dockerConfigDir = "$env:USERPROFILE\.docker"
$dockerConfigFile = "$dockerConfigDir\config.json"

# Create .docker directory if it doesn't exist
if (-not (Test-Path $dockerConfigDir)) {
    New-Item -ItemType Directory -Path $dockerConfigDir -Force | Out-Null
}

# Backup existing config
if (Test-Path $dockerConfigFile) {
    Copy-Item $dockerConfigFile "$dockerConfigFile.backup"
    Write-Info "Backed up existing config to $dockerConfigFile.backup"
    
    # Read existing config
    $config = Get-Content $dockerConfigFile -Raw | ConvertFrom-Json
} else {
    $config = [PSCustomObject]@{}
}

# Add proxy configuration
$proxyConfig = @{
    httpProxy = "http://${ProxyHost}:${ProxyPort}"
    httpsProxy = "http://${ProxyHost}:${ProxyPort}"
    noProxy = "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local"
}

$config | Add-Member -NotePropertyName "proxies" -NotePropertyValue @{
    default = $proxyConfig
} -Force

# Write updated config
$config | ConvertTo-Json -Depth 10 | Set-Content $dockerConfigFile -Encoding UTF8
Write-Info "Docker config updated with proxy settings"

# ============================================
# Restart Docker Desktop
# ============================================
Write-Host ""
Write-Warn "Docker Desktop needs to be restarted for changes to take effect."
Write-Host ""

$restart = Read-Host "Would you like to restart Docker Desktop now? (y/N)"
if ($restart -eq "y" -or $restart -eq "Y") {
    Write-Info "Restarting Docker Desktop..."
    
    # Stop Docker Desktop
    Get-Process "Docker Desktop" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Start Docker Desktop
    $dockerDesktopPath = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerDesktopPath)) {
        $dockerDesktopPath = "${env:LOCALAPPDATA}\Programs\Docker\Docker\Docker Desktop.exe"
    }
    
    if (Test-Path $dockerDesktopPath) {
        Start-Process $dockerDesktopPath
        Write-Info "Docker Desktop is starting..."
        Write-Info "Please wait for Docker to be fully ready before testing."
    } else {
        Write-Warn "Could not find Docker Desktop executable. Please restart it manually."
    }
} else {
    Write-Warn "Please restart Docker Desktop manually for changes to take effect."
}

# ============================================
# Completion message
# ============================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Info "Docker is now configured to use the proxy at ${ProxyHost}:${ProxyPort}"
Write-Host ""
Write-Info "After Docker Desktop restarts, test by running:"
Write-Host "  docker pull hello-world"
Write-Host ""
Write-Info "To verify proxy configuration:"
Write-Host "  Get-Content ~/.docker/config.json"
Write-Host ""

# Cleanup
Remove-Item $tempCaCert -Force -ErrorAction SilentlyContinue
