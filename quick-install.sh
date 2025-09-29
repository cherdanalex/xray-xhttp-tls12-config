#!/bin/bash
# Quick installer for Xray XHTTP + TLS 1.2
# Downloads repository and runs deployment

set -e

echo "======================================================"
echo "Xray XHTTP + TLS 1.2 Quick Installer"
echo "======================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Create temporary directory
TMP_DIR="/tmp/xray-install-$(date +%s)"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "[1/4] Downloading installation files..."
curl -sL https://github.com/cherdanalex/xray-xhttp-tls12-config/archive/refs/heads/main.tar.gz | tar xz
cd xray-xhttp-tls12-config-main

echo "[2/4] Setting permissions..."
chmod +x scripts/*.sh

echo "[3/4] Starting deployment..."
echo ""
./scripts/deploy.sh

echo ""
echo "[4/4] Cleaning up..."
cd /
rm -rf "$TMP_DIR"

echo ""
echo "======================================================"
echo "Installation completed!"
echo "======================================================"
