#!/bin/bash
# Enhanced certificate update script for Xray server
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

# Load environment variables
if [[ -f ".env" ]]; then
    source .env
    log "INFO" "Loaded environment variables from .env"
else
    log "ERROR" ".env file not found. Please run deploy.sh first."
    exit 1
fi

if [[ -z "${DOMAIN:-}" ]]; then
    log "ERROR" "DOMAIN is not set in .env file"
    exit 1
fi

log "INFO" "Starting certificate update for domain: $DOMAIN"

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    log "ERROR" "Certbot is not installed. Please run deploy.sh first."
    exit 1
fi

# Check current certificate status
log "INFO" "Checking current certificate status..."
if certbot certificates | grep -q "$DOMAIN"; then
    log "INFO" "Certificate found for $DOMAIN"
    
    expiry_date=$(certbot certificates | grep -A 2 "$DOMAIN" | grep "Expiry Date" | awk '{print $3, $4, $5}')
    log "INFO" "Certificate expires: $expiry_date"
    
    # Calculate days until expiry
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %Y" "$expiry_date" +%s)
    current_epoch=$(date +%s)
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log "INFO" "Days until expiry: $days_until_expiry"
    
    # Only renew if certificate expires in less than 30 days
    if [[ $days_until_expiry -lt 30 ]]; then
        log "INFO" "Certificate expires soon, attempting renewal..."
        
        if nginx -t; then
            log "INFO" "Nginx configuration is valid"
        else
            log "ERROR" "Nginx configuration is invalid, skipping renewal"
            exit 1
        fi
        
        log "INFO" "Stopping Nginx for certificate renewal..."
        systemctl stop nginx
        
        if certbot renew --cert-name "$DOMAIN" --non-interactive --agree-tos; then
            log "INFO" "Certificate renewed successfully!"
            
            if nginx -t; then
                log "INFO" "Nginx configuration is valid after renewal"
                log "INFO" "Starting Nginx..."
                systemctl start nginx
                log "INFO" "Reloading Nginx configuration..."
                systemctl reload nginx
                log "INFO" "Certificate update completed successfully!"
            else
                log "ERROR" "Nginx configuration test failed after renewal!"
                log "ERROR" "Starting Nginx anyway..."
                systemctl start nginx
                exit 1
            fi
        else
            log "ERROR" "Certificate renewal failed!"
            log "INFO" "Starting Nginx anyway..."
            systemctl start nginx
            exit 1
        fi
    else
        log "INFO" "Certificate is still valid for $days_until_expiry days, no renewal needed"
    fi
else
    log "ERROR" "No certificate found for $DOMAIN"
    log "INFO" "Please run deploy.sh to create initial certificate"
    exit 1
fi

# Verify certificate is working
log "INFO" "Verifying certificate..."
if timeout 10 openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -dates; then
    log "INFO" "Certificate verification successful!"
else
    log "WARN" "Certificate verification failed, but renewal completed"
fi

log "INFO" "Certificate update script completed!"

# Add to crontab if not already present
log "INFO" "Checking crontab for automatic renewal..."
if ! crontab -l 2>/dev/null | grep -q "update-cert.sh"; then
    log "INFO" "Adding certificate renewal to crontab..."
    (crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/scripts/update-cert.sh >> /var/log/xray-deploy.log 2>&1") | crontab -
    log "INFO" "Added daily certificate check at 2:00 AM"
fi
