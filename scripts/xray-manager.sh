#!/bin/bash
# Xray Server Management Utility
# Provides easy management commands for the Xray server

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
ENV_FILE="$PROJECT_ROOT/.env"
LOG_FILE="/var/log/xray-deploy.log"

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
}

# Load configuration
load_config() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
        return 0
    else
        log "ERROR" "Configuration file not found: $ENV_FILE"
        return 1
    fi
}

# Show usage information
show_usage() {
    cat << USAGE_EOF
Xray Server Management Utility

Usage: $0 <command> [options]

Commands:
    status          Show status of all services
    restart         Restart Xray and Nginx services
    reload          Reload Xray configuration
    logs            Show recent logs
    config          Show current configuration
    client          Generate client configuration
    vless           Show VLESS link
    update-cert     Update SSL certificate
    firewall        Show firewall status
    backup          Backup current configuration
    restore         Restore configuration from backup
    help            Show this help message

Examples:
    $0 status                    # Check service status
    $0 restart                   # Restart services
    $0 logs                      # Show recent logs
    $0 client                    # Generate client config
    $0 vless                     # Show VLESS link

USAGE_EOF
}

# Check service status
check_status() {
    log "INFO" "Checking service status..."
    echo
    
    # Check Xray
    if systemctl is-active --quiet xray; then
        echo -e "Xray: ${GREEN}✓ Running${NC}"
    else
        echo -e "Xray: ${RED}✗ Not running${NC}"
    fi
    
    # Check Nginx
    if systemctl is-active --quiet nginx; then
        echo -e "Nginx: ${GREEN}✓ Running${NC}"
    else
        echo -e "Nginx: ${RED}✗ Not running${NC}"
    fi
    
    # Check SSL certificate
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        local cert_expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | cut -d= -f2)
        echo -e "SSL Certificate: ${GREEN}✓ Valid (expires: $cert_expiry)${NC}"
    else
        echo -e "SSL Certificate: ${RED}✗ Not found${NC}"
    fi
    
    # Check firewall
    if ufw status | grep -q "Status: active"; then
        echo -e "Firewall: ${GREEN}✓ Active${NC}"
    else
        echo -e "Firewall: ${YELLOW}⚠ Inactive${NC}"
    fi
    
    echo
}

# Restart services
restart_services() {
    log "INFO" "Restarting services..."
    
    systemctl restart nginx
    systemctl restart xray
    
    sleep 2
    
    if systemctl is-active --quiet nginx && systemctl is-active --quiet xray; then
        log "INFO" "Services restarted successfully"
    else
        log "ERROR" "Failed to restart services"
        systemctl status nginx --no-pager -l
        systemctl status xray --no-pager -l
    fi
}

# Reload Xray configuration
reload_xray() {
    log "INFO" "Reloading Xray configuration..."
    
    if systemctl reload xray; then
        log "INFO" "Xray configuration reloaded successfully"
    else
        log "ERROR" "Failed to reload Xray configuration"
        systemctl status xray --no-pager -l
    fi
}

# Show logs
show_logs() {
    local lines="${1:-50}"
    log "INFO" "Showing last $lines lines of logs..."
    echo
    
    echo -e "${BLUE}=== Xray Deploy Logs ===${NC}"
    tail -n "$lines" "$LOG_FILE" 2>/dev/null || echo "No deploy logs found"
    echo
    
    echo -e "${BLUE}=== Xray Service Logs ===${NC}"
    journalctl -u xray -n "$lines" --no-pager 2>/dev/null || echo "No Xray service logs found"
    echo
    
    echo -e "${BLUE}=== Nginx Service Logs ===${NC}"
    journalctl -u nginx -n "$lines" --no-pager 2>/dev/null || echo "No Nginx service logs found"
}

# Show configuration
show_config() {
    if load_config; then
        log "INFO" "Current configuration:"
        echo
        echo -e "Domain: ${BLUE}$DOMAIN${NC}"
        echo -e "Email: ${BLUE}$EMAIL${NC}"
        echo -e "SSH Port: ${BLUE}$SSH_PORT${NC}"
        echo -e "Xray UUID: ${BLUE}$XRAY_UUID${NC}"
        echo -e "Xray Port: ${BLUE}$XRAY_PORT${NC}"
        echo -e "Reality Public Key: ${BLUE}$REALITY_PUBLIC_KEY${NC}"
        echo -e "Reality Short ID: ${BLUE}$REALITY_SHORT_ID${NC}"
    else
        log "ERROR" "Failed to load configuration"
        exit 1
    fi
}

# Generate client configuration
generate_client() {
    if ! load_config; then
        log "ERROR" "Failed to load configuration"
        exit 1
    fi
    
    log "INFO" "Generating client configuration..."
    
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

    log "INFO" "Client configuration saved to: $PROJECT_ROOT/client-configs/xray-client.json"
}

# Generate VLESS link
generate_vless() {
    if ! load_config; then
        log "ERROR" "Failed to load configuration"
        exit 1
    fi
    
    local vless_link="vless://${XRAY_UUID}@${DOMAIN}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&spx=%2F&type=xhttp&headerType=none&fp=chrome#Xray-XHTTP"
    
    echo -e "${GREEN}=== VLESS LINK ===${NC}"
    echo -e "${BLUE}$vless_link${NC}"
    echo
    
    # Save to file
    echo "$vless_link" > "$PROJECT_ROOT/client-configs/vless-link.txt"
    log "INFO" "VLESS link saved to: $PROJECT_ROOT/client-configs/vless-link.txt"
}

# Update SSL certificate
update_certificate() {
    log "INFO" "Updating SSL certificate..."
    
    if certbot renew --quiet; then
        log "INFO" "SSL certificate updated successfully"
        systemctl reload nginx
    else
        log "ERROR" "Failed to update SSL certificate"
        exit 1
    fi
}

# Show firewall status
show_firewall() {
    log "INFO" "Firewall status:"
    echo
    ufw status verbose
}

# Backup configuration
backup_config() {
    local backup_dir="$PROJECT_ROOT/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/xray-config-$timestamp.tar.gz"
    
    log "INFO" "Creating backup..."
    
    mkdir -p "$backup_dir"
    
    tar -czf "$backup_file" \
        -C "$PROJECT_ROOT" \
        .env \
        client-configs/ \
        configs/ \
        /etc/xray/config.json \
        /etc/nginx/sites-available/xray-proxy \
        2>/dev/null || true
    
    log "INFO" "Backup created: $backup_file"
}

# Restore configuration
restore_config() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup file not found: $backup_file"
        exit 1
    fi
    
    log "INFO" "Restoring from backup: $backup_file"
    
    # Stop services
    systemctl stop xray nginx
    
    # Extract backup
    tar -xzf "$backup_file" -C "$PROJECT_ROOT"
    
    # Restart services
    systemctl start nginx xray
    
    log "INFO" "Configuration restored successfully"
}

# Main function
main() {
    local command="${1:-help}"
    
    case "$command" in
        "status")
            check_status
            ;;
        "restart")
            restart_services
            ;;
        "reload")
            reload_xray
            ;;
        "logs")
            show_logs "${2:-50}"
            ;;
        "config")
            show_config
            ;;
        "client")
            generate_client
            ;;
        "vless")
            generate_vless
            ;;
        "update-cert")
            update_certificate
            ;;
        "firewall")
            show_firewall
            ;;
        "backup")
            backup_config
            ;;
        "restore")
            if [[ -z "${2:-}" ]]; then
                log "ERROR" "Please specify backup file path"
                exit 1
            fi
            restore_config "$2"
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
