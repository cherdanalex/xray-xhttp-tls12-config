#!/bin/bash
# Enhanced Xray Server Deployment Script
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> /var/log/xray-deploy.log
}

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
    exit 1
fi

mkdir -p /var/log/xray
touch /var/log/xray-deploy.log
chmod 644 /var/log/xray-deploy.log
# Clean up old configurations
# Stop Nginx if running
systemctl stop nginx 2>/dev/null || true

log "INFO" "Cleaning up old configurations..."

# Remove old Nginx configurations that might conflict
if [ -f "/etc/nginx/sites-enabled/xray-xhttp-proxy" ]; then
    rm -f /etc/nginx/sites-enabled/xray-xhttp-proxy
    log "INFO" "Removed old xray-xhttp-proxy configuration"
fi

if [ -f "/etc/nginx/sites-available/xray-xhttp-proxy" ]; then
    rm -f /etc/nginx/sites-available/xray-xhttp-proxy
    log "INFO" "Removed old xray-xhttp-proxy from sites-available"
fi

# Remove symlinks to xray-proxy if they exist
if [ -L "/etc/nginx/sites-enabled/xray-proxy" ]; then
    rm -f /etc/nginx/sites-enabled/xray-proxy

# Clean up nginx.conf if it has broken includes
if [ -f "/etc/nginx/nginx.conf" ]; then
    # Remove any broken include lines for xray configs
    sed -i '/xray-xhttp-proxy/d' /etc/nginx/nginx.conf
    sed -i '/xray-proxy/d' /etc/nginx/nginx.conf
    log "INFO" "Cleaned up nginx.conf includes"
fi

# Also remove any broken site configs
rm -f /etc/nginx/sites-enabled/xray-* 2>/dev/null || true
rm -f /etc/nginx/sites-available/xray-* 2>/dev/null || true
log "INFO" "Removed all old xray configurations"

    log "INFO" "Removed old xray-proxy symlink"
fi


log "INFO" "Starting Xray server deployment..."

# Check for corrupted .env file
if [[ -f ".env" ]]; then
    if grep -q "^[^#]*[^=]*[^=]$" .env 2>/dev/null; then
        log "WARN" "Corrupted .env file detected. Removing it."
        rm -f .env
    fi
fi

# Check if .env exists
if [[ -f ".env" ]]; then
    log "WARN" ".env file already exists. Loading existing configuration..."
    source .env 2>/dev/null || log "ERROR" "Failed to load .env file"
    # Validate .env file format before sourcing
    if grep -q "^[^=]*[^=]$" .env 2>/dev/null; then
        log "ERROR" "Invalid .env file format detected. Removing corrupted file."
        rm -f .env
        RECONFIGURE=true
    fi
    # Check if variables are loaded correctly
    if [[ -z "${DOMAIN:-}" ]]; then
        log "WARN" "DOMAIN not found in .env, will reconfigure"
        RECONFIGURE=true
    else
        log "INFO" "Loaded existing configuration:"
        log "INFO" "  DOMAIN: ${DOMAIN:-'not set'}"
        log "INFO" "  EMAIL: ${EMAIL:-'not set'}"
        log "INFO" "  SSH_PORT: ${SSH_PORT:-'not set'}"
        log "INFO" "  XRAY_UUID: ${XRAY_UUID:-'not set'}"
        log "INFO" "  XRAY_PORT: ${XRAY_PORT:-'not set'}"
    fi
    read -p "Do you want to reconfigure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Using existing configuration..."
        RECONFIGURE=false
    else
        RECONFIGURE=true
    fi
else
    RECONFIGURE=true
fi

# Get configuration from user
if [[ "$RECONFIGURE" == "true" ]]; then
    log "INFO" "Gathering configuration..."
    
    # Get domain
    while true; do
        echo -n "Enter your domain name (e.g., example.com): "
        read DOMAIN
        if [[ -n "$DOMAIN" && "$DOMAIN" != "" ]]; then
            break
        else
            log "ERROR" "Domain cannot be empty. Please try again."
        fi
    done
    
    # Get email
    while true; do
        echo -n "Enter your email for Let's Encrypt: "
        read EMAIL
        if [[ -n "$EMAIL" && "$EMAIL" == *"@"* && "$EMAIL" == *"."* ]]; then
            break
        else
            log "ERROR" "Invalid email address. Please try again."
            log "INFO" "Email format should be: user@domain.com"
        fi
    done
    
    # Get SSH port
    echo -n "Enter SSH port (default: 22): "
    read SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    
    # Get or generate UUID
    echo -n "Enter UUID for Xray client (press Enter to generate): "
    read XRAY_UUID
    if [[ -z "$XRAY_UUID" ]]; then
        XRAY_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
        log "INFO" "Generated UUID: $XRAY_UUID"
    fi
    
    # Get Xray port
    echo -n "Enter Xray internal port (default: 10000): "
    read XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-10000}
    
    # Generate Reality keys (simplified)
    REALITY_PRIVATE_KEY=$(openssl rand -base64 32)
    REALITY_PUBLIC_KEY=$(echo "$REALITY_PRIVATE_KEY" | openssl dgst -sha256 -binary | base64)
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    
    # Save configuration to .env (safer method)
    {
        echo "# Xray Server Configuration"
        echo "# Generated on $(date)"
        echo ""
        echo "DOMAIN=$DOMAIN"
        echo "EMAIL=$EMAIL"
        echo "SSH_PORT=$SSH_PORT"
        echo "XRAY_UUID=$XRAY_UUID"
        echo "XRAY_PORT=$XRAY_PORT"
        echo ""
        echo "# Reality Keys (DO NOT SHARE)"
        echo "REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY"
        echo "REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY"
        echo "REALITY_SHORT_ID=$REALITY_SHORT_ID"
    } > .env
    
    log "INFO" "Configuration saved to .env file"
fi

# Update system
log "INFO" "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
log "INFO" "Installing required packages..."
apt-get install -y curl wget unzip openssl nginx certbot python3-certbot-nginx ufw

# Install Xray
log "INFO" "Installing Xray..."
if ! command -v xray &> /dev/null; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    systemctl enable xray
else
    log "INFO" "Xray is already installed"
fi


# Setup firewall (inline)
log "INFO" "Setting up firewall..."

# Install UFW if not present
if ! command -v ufw &> /dev/null; then
    log "INFO" "Installing UFW..."
    apt-get update -qq
    apt-get install -y -qq ufw
fi

# Function to check if rule exists
rule_exists() {
    local port="$1"
    local protocol="${2:-tcp}"
    ufw status numbered 2>/dev/null | grep -q "${port}/${protocol}"
}

# Function to add rule if not exists
add_rule_if_not_exists() {
    local port="$1"
    local protocol="${2:-tcp}"
    local description="$3"
    
    if rule_exists "$port" "$protocol"; then
        log "INFO" "Rule for $port/$protocol already exists"
        return 0
    else
        log "INFO" "Adding rule: $description"
        ufw allow "$port/$protocol" comment "$description" 2>/dev/null || true
        return 1
    fi
}

# Check if UFW is already active
if ufw status 2>/dev/null | grep -q "Status: active"; then
    log "INFO" "UFW is active, checking rules..."
    add_rule_if_not_exists "$SSH_PORT" "tcp" "SSH"
    add_rule_if_not_exists "80" "tcp" "HTTP"
    add_rule_if_not_exists "443" "tcp" "HTTPS"
    add_rule_if_not_exists "$XRAY_PORT" "tcp" "Xray"
else
    log "INFO" "Setting up UFW..."
    ufw --force reset 2>/dev/null || true
    ufw default deny incoming
    ufw default allow outgoing
    ufw logging on
    ufw allow "$SSH_PORT/tcp" comment "SSH"
    ufw allow "80/tcp" comment "HTTP"
    ufw allow "443/tcp" comment "HTTPS"
    ufw allow "$XRAY_PORT/tcp" comment "Xray"
    ufw --force enable
fi

log "INFO" "Firewall setup completed"
if [[ "$SSH_PORT" != "22" ]]; then
    log "WARN" "SSH port is $SSH_PORT (not 22)"
fi

# Setup Nginx
# Export variables for envsubst
export DOMAIN XRAY_PORT XRAY_UUID REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
log "INFO" "Configuring Nginx (initial HTTP-only setup)..."

# Create initial HTTP-only configuration for Certbot
cat > /etc/nginx/sites-available/xray-proxy << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 200 'Server is being configured...';
        add_header Content-Type text/plain;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/xray-proxy /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and start Nginx
if nginx -t; then
    log "INFO" "Nginx configuration is valid"
else
    log "ERROR" "Nginx configuration test failed!"
    exit 1
fi

systemctl start nginx
systemctl enable nginx

# Get SSL certificate
log "INFO" "Obtaining SSL certificate from Let's Encrypt..."
if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
    log "INFO" "SSL certificate obtained successfully!"
else
    log "ERROR" "Failed to obtain SSL certificate"
    log "INFO" "Please check:"
    log "INFO" "1. Domain $DOMAIN points to this server"
    log "INFO" "2. Port 80 is accessible"
    log "INFO" "3. No rate limit issues with Let's Encrypt"
    exit 1
fi

# Now create full Xray proxy configuration with SSL
log "INFO" "Creating Xray proxy configuration with SSL..."
envsubst '${DOMAIN} ${XRAY_PORT}' < configs/nginx-xray-proxy.conf.example > /etc/nginx/sites-available/xray-proxy

# Test and reload Nginx
if nginx -t; then
    systemctl reload nginx
    log "INFO" "Nginx reloaded with Xray proxy configuration"
else
    log "ERROR" "Nginx configuration test failed after adding Xray proxy"
    exit 1
fi
# Create Xray configuration
log "INFO" "Creating Xray server configuration..."
mkdir -p /etc/xray
envsubst '${XRAY_PORT} ${XRAY_UUID} ${DOMAIN} ${REALITY_PRIVATE_KEY} ${REALITY_SHORT_ID}' < configs/xray-server.json.example > /etc/xray/config.json

mkdir -p /var/log/xray
chown xray:xray /var/log/xray

cp systemd/xray.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable xray
systemctl start xray

# Setup certificate auto-renewal
chmod +x scripts/update-cert.sh
(crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/scripts/update-cert.sh >> /var/log/xray-deploy.log 2>&1") | crontab -

# Create client configuration
mkdir -p client-configs
envsubst '${DOMAIN} ${XRAY_UUID} ${REALITY_PUBLIC_KEY} ${REALITY_SHORT_ID}' < configs/xray-client.json.example > client-configs/xray-client.json

log "INFO" "Deployment completed successfully!"
echo
echo -e "${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Xray UUID: ${GREEN}$XRAY_UUID${NC}"
echo -e "Xray Port: ${GREEN}$XRAY_PORT${NC}"
echo -e "Reality Public Key: ${GREEN}$REALITY_PUBLIC_KEY${NC}"
echo -e "Reality Short ID: ${GREEN}$REALITY_SHORT_ID${NC}"
echo
echo -e "${YELLOW}Client configuration saved to: client-configs/xray-client.json${NC}"
echo -e "${GREEN}Deployment completed at $(date)${NC}"
