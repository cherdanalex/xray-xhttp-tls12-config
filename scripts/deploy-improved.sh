#!/bin/bash
# Enhanced Xray Server Deployment Script with XHTTP support
# Improved version with modular functions, idempotency, and better UX

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/xray-deploy.log"
ENV_FILE="$PROJECT_ROOT/.env"

# Default values
DEFAULT_SSH_PORT=22
DEFAULT_XRAY_PORT=10000
DEFAULT_DOMAIN=""
DEFAULT_EMAIL=""

# Command line flags
AUTO_MODE=false
REINSTALL_MODE=false
SKIP_SSL=false

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Show usage information
show_usage() {
    cat << USAGE_EOF
Usage: $0 [OPTIONS]

Options:
    --auto          Run in automatic mode with defaults (no prompts)
    --reinstall     Remove existing installation and reinstall
    --skip-ssl      Skip SSL certificate generation (for testing)
    --help          Show this help message

Examples:
    $0                    # Interactive mode
    $0 --auto             # Automatic mode with defaults
    $0 --reinstall        # Clean reinstall
    $0 --auto --skip-ssl  # Auto mode without SSL

USAGE_EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --reinstall)
                REINSTALL_MODE=true
                shift
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Initialize logging
init_logging() {
    mkdir -p /var/log/xray
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    log "INFO" "Starting Xray XHTTP server deployment..."
}

# Validate domain format
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# Validate email format
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Check if package is installed
is_package_installed() {
    local package="$1"
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Check if service is running
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# Get configuration from user or use defaults
get_configuration() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        log "INFO" "Running in automatic mode with defaults..."
        DOMAIN="${DEFAULT_DOMAIN:-example.com}"
        EMAIL="${DEFAULT_EMAIL:-admin@example.com}"
        SSH_PORT="$DEFAULT_SSH_PORT"
        XRAY_PORT="$DEFAULT_XRAY_PORT"
        XRAY_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    else
        # Interactive mode
        log "INFO" "Gathering configuration..."
        
        # Get domain
        while true; do
            echo -n "Enter your domain name (e.g., example.com): "
            read DOMAIN
            if [[ -n "$DOMAIN" && "$DOMAIN" != "" ]]; then
                if validate_domain "$DOMAIN"; then
                    break
                else
                    log "ERROR" "Invalid domain format. Please use format like example.com"
                fi
            else
                log "ERROR" "Domain cannot be empty. Please try again."
            fi
        done
        
        # Get email
        while true; do
            echo -n "Enter your email for Let's Encrypt: "
            read EMAIL
            if [[ -n "$EMAIL" && "$EMAIL" != "" ]]; then
                if validate_email "$EMAIL"; then
                    break
                else
                    log "ERROR" "Invalid email format. Please use format like user@domain.com"
                fi
            else
                log "ERROR" "Email cannot be empty. Please try again."
            fi
        done
        
        # Get SSH port
        echo -n "Enter SSH port (default: $DEFAULT_SSH_PORT): "
        read SSH_PORT
        SSH_PORT=${SSH_PORT:-$DEFAULT_SSH_PORT}
        
        # Get or generate UUID
        echo -n "Enter UUID for Xray client (press Enter to generate): "
        read XRAY_UUID
        if [[ -z "$XRAY_UUID" ]]; then
            XRAY_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
            log "INFO" "Generated UUID: $XRAY_UUID"
        fi
        
        # Get Xray port
        echo -n "Enter Xray internal port (default: $DEFAULT_XRAY_PORT): "
        read XRAY_PORT
        XRAY_PORT=${XRAY_PORT:-$DEFAULT_XRAY_PORT}
    fi
    
    # Generate Reality keys
    log "INFO" "Generating Reality keys..."
    REALITY_PRIVATE_KEY=$(openssl rand -base64 32)
    REALITY_PUBLIC_KEY=$(echo "$REALITY_PRIVATE_KEY" | openssl dgst -sha256 -binary | base64)
    REALITY_SHORT_ID=$(openssl rand -hex 8)
}

# Save configuration to .env file
save_configuration() {
    log "INFO" "Saving configuration to .env file..."
    {
        echo "# Xray XHTTP Server Configuration"
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
    } > "$ENV_FILE"
    
    chmod 600 "$ENV_FILE"
    log "INFO" "Configuration saved to .env file"
}

# Load existing configuration
load_existing_config() {
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Loading existing configuration from .env..."
        set +e
        source "$ENV_FILE" 2>/dev/null
        set -e
        
        if [[ -n "${DOMAIN:-}" && -n "${EMAIL:-}" ]]; then
            log "INFO" "Loaded existing configuration:"
            log "INFO" "  DOMAIN: $DOMAIN"
            log "INFO" "  EMAIL: $EMAIL"
            log "INFO" "  SSH_PORT: ${SSH_PORT:-$DEFAULT_SSH_PORT}"
            log "INFO" "  XRAY_UUID: ${XRAY_UUID:-'not set'}"
            log "INFO" "  XRAY_PORT: ${XRAY_PORT:-$DEFAULT_XRAY_PORT}"
            return 0
        else
            log "WARN" "Invalid or incomplete .env file"
            return 1
        fi
    fi
    return 1
}

# Check if Xray is already installed and running
check_existing_installation() {
    if is_service_running "xray" && is_service_running "nginx"; then
        log "WARN" "Xray and Nginx are already running!"
        if [[ "$REINSTALL_MODE" == "true" ]]; then
            log "INFO" "Reinstall mode: will stop services and reconfigure"
            return 1
        else
            echo -n "Do you want to update configuration only? (y/N): "
            read -r REPLY
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Updating configuration only..."
                return 0
            else
                log "INFO" "Full reinstall requested..."
                return 1
            fi
        fi
    fi
    return 1
}

# Stop existing services
stop_services() {
    log "INFO" "Stopping existing services..."
    systemctl stop xray 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
}

# Update system packages
update_system() {
    log "INFO" "Updating system packages..."
    apt-get update -qq
    apt-get upgrade -y -qq
}

# Install required packages
install_packages() {
    local packages=("curl" "wget" "unzip" "openssl" "nginx" "certbot" "python3-certbot-nginx" "ufw" "uuid-runtime")
    local packages_to_install=()
    
    log "INFO" "Checking required packages..."
    for package in "${packages[@]}"; do
        if ! is_package_installed "$package"; then
            packages_to_install+=("$package")
        else
            log "INFO" "$package is already installed"
        fi
    done
    
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log "INFO" "Installing missing packages: ${packages_to_install[*]}"
        apt-get install -y -qq "${packages_to_install[@]}"
    else
        log "INFO" "All required packages are already installed"
    fi
}

# Install Xray
install_xray() {
    log "INFO" "Installing Xray..."
    if ! command -v xray &> /dev/null; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        systemctl enable xray
        log "INFO" "Xray installed successfully"
    else
        log "INFO" "Xray is already installed"
    fi
}

# Setup Xray user and directories
setup_xray_user() {
    if ! id -u xray &> /dev/null; then
        log "INFO" "Creating xray system user..."
        useradd -r -M -s /usr/sbin/nologin xray
    else
        log "INFO" "User xray already exists"
    fi
    
    log "INFO" "Setting up Xray directories..."
    mkdir -p /etc/xray
    mkdir -p /var/log/xray
    chown -R xray:xray /etc/xray /var/log/xray
    chmod 755 /etc/xray /var/log/xray
}

# Setup firewall with idempotency
setup_firewall() {
    log "INFO" "Setting up firewall..."
    
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
            log "INFO" "Rule for $port/$protocol already exists, skipping..."
            return 0
        else
            log "INFO" "Adding rule: $description"
            ufw allow "$port/$protocol" comment "$description" 2>/dev/null || true
            return 1
        fi
    }
    
    # Check if UFW is already configured
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log "INFO" "UFW is already active, checking for existing rules..."
        
        add_rule_if_not_exists "$SSH_PORT" "tcp" "SSH access"
        add_rule_if_not_exists "80" "tcp" "HTTP"
        add_rule_if_not_exists "443" "tcp" "HTTPS"
        # Note: XRAY_PORT should NOT be exposed externally in xHTTP architecture
        # It should only be accessible from localhost (127.0.0.1)
    else
        log "INFO" "Setting up UFW for the first time..."
        
        # Reset UFW to clean state
        ufw --force reset 2>/dev/null || true
        
        # Set default policies
        ufw default deny incoming
        ufw default allow outgoing
        ufw default deny forward
        
        # Enable logging
        ufw logging on
        
        log "INFO" "Adding essential firewall rules..."
        
        # SSH access (critical - add first)
        ufw allow "$SSH_PORT/tcp" comment "SSH access"
        
        # HTTP and HTTPS
        ufw allow "80/tcp" comment "HTTP"
        ufw allow "443/tcp" comment "HTTPS"
        
        # Enable UFW
        log "INFO" "Enabling UFW..."
        ufw --force enable
    fi
    
    log "INFO" "Firewall setup completed!"
    if [[ "$SSH_PORT" != "22" ]]; then
        log "WARN" "SSH is configured on port $SSH_PORT, not the default 22!"
    fi
}

# Configure Nginx
configure_nginx() {
    log "INFO" "Configuring Nginx..."
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/xray-proxy << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL Configuration (will be configured by certbot)
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # TLS 1.2 and 1.3 configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Hide server version
    server_tokens off;

    # Proxy settings for Xray
    location / {
        proxy_pass http://127.0.0.1:${XRAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts for XHTTP
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings for XHTTP
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }

    # Block access to hidden files
    location ~ /\\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/xray-proxy /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test Nginx configuration
    if nginx -t; then
        log "INFO" "Nginx configuration is valid"
    else
        log "ERROR" "Nginx configuration test failed!"
        exit 1
    fi
    
    # Start Nginx
    systemctl start nginx
    systemctl enable nginx
}

# Get SSL certificate
get_ssl_certificate() {
    if [[ "$SKIP_SSL" == "true" ]]; then
        log "WARN" "Skipping SSL certificate generation (--skip-ssl flag)"
        return 0
    fi
    
    log "INFO" "Obtaining SSL certificate from Let's Encrypt..."
    
    # Check if certificate already exists and is valid
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        local cert_age=$(($(date +%s) - $(stat -c %Y "/etc/letsencrypt/live/$DOMAIN/fullchain.pem")))
        if [[ $cert_age -lt 2592000 ]]; then  # 30 days
            log "INFO" "SSL certificate is still valid (less than 30 days old)"
            return 0
        else
            log "INFO" "SSL certificate is older than 30 days, renewing..."
        fi
    fi
    
    # Try to get certificate
    if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
        log "INFO" "SSL certificate obtained successfully"
    else
        log "ERROR" "Failed to obtain SSL certificate"
        log "INFO" "Trying standalone mode as fallback..."
        
        # Stop nginx temporarily for standalone mode
        systemctl stop nginx
        
        if certbot certonly --standalone -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive; then
            log "INFO" "SSL certificate obtained in standalone mode"
            systemctl start nginx
        else
            log "ERROR" "Failed to obtain SSL certificate in standalone mode"
            log "INFO" "Please check:"
            log "INFO" "1. Domain $DOMAIN points to this server's IP"
            log "INFO" "2. Port 80 is accessible"
            log "INFO" "3. No rate limit issues with Let's Encrypt"
            systemctl start nginx
            exit 1
        fi
    fi
}

# Create Xray configuration
create_xray_config() {
    log "INFO" "Creating Xray server configuration..."
    
    cat > /etc/xray/config.json << XRAYEOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${XRAY_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DOMAIN}:443",
          "xver": 0,
          "serverNames": [
            "${DOMAIN}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID}"
          ]
        },
        "xhttpSettings": {
          "mode": "stream-up"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
XRAYEOF

    # Copy systemd service
    log "INFO" "Setting up Xray systemd service..."
    cp "$PROJECT_ROOT/systemd/xray.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable xray
}

# Start Xray service
start_xray() {
    log "INFO" "Starting Xray service..."
    systemctl start xray
    
    # Wait a moment for service to start
    sleep 2
    
    if systemctl is-active --quiet xray; then
        log "INFO" "Xray service started successfully"
    else
        log "ERROR" "Failed to start Xray service"
        systemctl status xray --no-pager -l
        exit 1
    fi
}

# Setup certificate auto-renewal
setup_auto_renewal() {
    log "INFO" "Setting up certificate auto-renewal..."
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/certbot renew --quiet && /usr/bin/systemctl reload nginx") | crontab -
        log "INFO" "Added certificate renewal cron job"
    else
        log "INFO" "Certificate renewal cron job already exists"
    fi
    
    # Add system update cron job
    if ! crontab -l 2>/dev/null | grep -q "apt upgrade"; then
        (crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/bin/apt update -qq && /usr/bin/apt upgrade -y -qq && /usr/bin/systemctl restart xray nginx") | crontab -
        log "INFO" "Added system update cron job"
    else
        log "INFO" "System update cron job already exists"
    fi
}

# Generate VLESS link
generate_vless_link() {
    local vless_link="vless://${XRAY_UUID}@${DOMAIN}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&spx=%2F&type=xhttp&headerType=none&fp=chrome#Xray-XHTTP"
    echo "$vless_link"
}

# Create client configuration
create_client_config() {
    log "INFO" "Creating client configuration..."
    mkdir -p "$PROJECT_ROOT/client-configs"
    
    cat > "$PROJECT_ROOT/client-configs/xray-client.json" << CLIENTEOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "port": 10809,
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${DOMAIN}",
            "port": 443,
            "users": [
              {
                "id": "${XRAY_UUID}",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverName": "${DOMAIN}",
          "publicKey": "${REALITY_PUBLIC_KEY}",
          "shortId": "${REALITY_SHORT_ID}",
          "spiderX": "/"
        },
        "xhttpSettings": {
          "mode": "stream-up",
          "path": "/",
          "keepAlivePeriod": 300
        }
      }
    }
  ]
}
CLIENTEOF

    # Generate VLESS link
    local vless_link=$(generate_vless_link)
    echo "$vless_link" > "$PROJECT_ROOT/client-configs/vless-link.txt"
    
    log "INFO" "Client configuration saved to: $PROJECT_ROOT/client-configs/"
}

# Check services status
check_services_status() {
    log "INFO" "Checking services status..."
    local all_good=true
    
    if systemctl is-active --quiet nginx; then
        log "INFO" "✓ Nginx is running"
    else
        log "ERROR" "✗ Nginx is not running"
        all_good=false
    fi
    
    if systemctl is-active --quiet xray; then
        log "INFO" "✓ Xray is running"
    else
        log "ERROR" "✗ Xray is not running"
        all_good=false
    fi
    
    if [[ "$all_good" == "true" ]]; then
        log "INFO" "All services are running successfully!"
    else
        log "WARN" "Some services may not be running properly"
        systemctl status nginx --no-pager -l || true
        systemctl status xray --no-pager -l || true
    fi
}

# Display final information
display_summary() {
    local vless_link=$(generate_vless_link)
    
    log "INFO" "Deployment completed successfully!"
    echo
    echo -e "${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
    echo -e "Domain: ${BLUE}$DOMAIN${NC}"
    echo -e "Xray UUID: ${BLUE}$XRAY_UUID${NC}"
    echo -e "Xray Port: ${BLUE}$XRAY_PORT${NC}"
    echo -e "Reality Public Key: ${BLUE}$REALITY_PUBLIC_KEY${NC}"
    echo -e "Reality Short ID: ${BLUE}$REALITY_SHORT_ID${NC}"
    echo
    echo -e "${YELLOW}Client configuration saved to: $PROJECT_ROOT/client-configs/${NC}"
    echo -e "${YELLOW}VLESS link saved to: $PROJECT_ROOT/client-configs/vless-link.txt${NC}"
    echo
    echo -e "${GREEN}=== VLESS LINK ===${NC}"
    echo -e "${BLUE}$vless_link${NC}"
    echo
    echo -e "${GREEN}=== IMPORTANT NOTES ===${NC}"
    echo -e "1. Make sure your domain $DOMAIN points to this server's IP"
    echo -e "2. SSH is configured on port $SSH_PORT"
    echo -e "3. Firewall rules have been applied"
    echo -e "4. Client configuration: $PROJECT_ROOT/client-configs/xray-client.json"
    echo -e "5. Logs: $LOG_FILE"
    echo
    echo -e "${GREEN}=== NEXT STEPS ===${NC}"
    echo -e "1. Test your connection using the VLESS link or client configuration"
    echo -e "2. Set up your Xray client with the provided configuration"
    echo -e "3. Monitor logs: tail -f $LOG_FILE"
    echo
    echo -e "${GREEN}Deployment completed at $(date)${NC}"
}

# Main deployment function
deploy_xray() {
    # Check if we should update configuration only
    if check_existing_installation; then
        log "INFO" "Updating configuration only..."
        create_xray_config
        systemctl reload xray
        create_client_config
        display_summary
        return 0
    fi
    
    # Full installation
    if [[ "$REINSTALL_MODE" == "true" ]]; then
        stop_services
    fi
    
    update_system
    install_packages
    install_xray
    setup_xray_user
    setup_firewall
    configure_nginx
    get_ssl_certificate
    create_xray_config
    start_xray
    setup_auto_renewal
    create_client_config
    check_services_status
    display_summary
}

# Main function
main() {
    parse_args "$@"
    check_root
    init_logging
    
    # Try to load existing configuration first
    if load_existing_config; then
        if [[ "$AUTO_MODE" == "true" || "$REINSTALL_MODE" == "true" ]]; then
            log "INFO" "Using existing configuration"
        else
            echo -n "Use existing configuration? (Y/n): "
            read -r REPLY
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                log "INFO" "Using existing configuration..."
            else
                get_configuration
                save_configuration
            fi
        fi
    else
        get_configuration
        save_configuration
    fi
    
    # Export variables for use in functions
    export DOMAIN EMAIL SSH_PORT XRAY_UUID XRAY_PORT
    export REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY REALITY_SHORT_ID
    
    deploy_xray
}

# Run main function with all arguments
main "$@"
