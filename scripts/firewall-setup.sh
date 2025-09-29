#!/bin/bash
# Enhanced firewall setup script for Xray server
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

SSH_PORT=${SSH_PORT:-22}
XRAY_PORT=${XRAY_PORT:-10000}

log "INFO" "Starting firewall setup..."
log "INFO" "SSH Port: $SSH_PORT"
log "INFO" "Xray Port: $XRAY_PORT"

# Check if UFW is installed
if ! command -v ufw &> /dev/null; then
    log "INFO" "Installing UFW..."
    apt-get update
    apt-get install -y ufw
fi

# Function to check if rule exists (idempotency)
rule_exists() {
    local port="$1"
    local protocol="${2:-tcp}"
    ufw status numbered | grep -q "$port/$protocol"
}

# Function to add rule if not exists (idempotency)
add_rule_if_not_exists() {
    local port="$1"
    local protocol="${2:-tcp}"
    local description="$3"
    
    if rule_exists "$port" "$protocol"; then
        log "INFO" "Rule for $port/$protocol already exists, skipping..."
        return 0
    else
        log "INFO" "Adding rule: $description"
        ufw allow "$port/$protocol" comment "$description"
        return 1
    fi
}

# Check if UFW is already configured
if ufw status | grep -q "Status: active"; then
    log "INFO" "UFW is already active, checking for existing rules..."
    
    rules_added=false
    add_rule_if_not_exists "$SSH_PORT" "tcp" "SSH access" || rules_added=true
    add_rule_if_not_exists "80" "tcp" "HTTP" || rules_added=true
    add_rule_if_not_exists "443" "tcp" "HTTPS" || rules_added=true
    add_rule_if_not_exists "$XRAY_PORT" "tcp" "Xray internal port" || rules_added=true
    add_rule_if_not_exists "53" "udp" "DNS" || rules_added=true
    
    if [[ "$rules_added" == "false" ]]; then
        log "INFO" "All required rules already exist, no changes needed"
    else
        log "INFO" "Added new firewall rules"
    fi
else
    log "INFO" "Setting up UFW for the first time..."
    
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny forward
    ufw logging on
    
    log "INFO" "Adding essential firewall rules..."
    
    ufw allow "$SSH_PORT/tcp" comment "SSH access"
    ufw allow "80/tcp" comment "HTTP"
    ufw allow "443/tcp" comment "HTTPS"
    ufw allow "$XRAY_PORT/tcp" comment "Xray internal port"
    ufw allow "53/udp" comment "DNS"
    ufw allow "67/udp" comment "DHCP server"
    ufw allow "68/udp" comment "DHCP client"
    
    log "INFO" "Enabling UFW..."
    ufw --force enable
fi

# Save current rules to config file
log "INFO" "Saving current rules to configs/ufw-rules.conf..."
cat > configs/ufw-rules.conf << RULESEOF
# UFW Rules for Xray Server
# Generated on $(date)
# DO NOT EDIT MANUALLY - Use firewall-setup.sh instead

# Default policies
DEFAULT_INPUT_POLICY=DENY
DEFAULT_FORWARD_POLICY=DENY
DEFAULT_OUTPUT_POLICY=ALLOW

# Ports configuration
SSH_PORT=$SSH_PORT
XRAY_PORT=$XRAY_PORT
HTTP_PORT=80
HTTPS_PORT=443
DNS_PORT=53

# Current active rules:
RULESEOF

ufw status numbered >> configs/ufw-rules.conf

log "INFO" "Firewall setup completed!"
ufw status

log "INFO" "Firewall rules saved to configs/ufw-rules.conf"
log "INFO" "IMPORTANT: Make sure SSH port $SSH_PORT is accessible before disconnecting!"

if [[ "$SSH_PORT" != "22" ]]; then
    log "WARN" "SSH is configured on port $SSH_PORT, not the default 22!"
    log "WARN" "Make sure your SSH client is configured to use port $SSH_PORT"
fi

log "INFO" "Firewall setup completed successfully!"
