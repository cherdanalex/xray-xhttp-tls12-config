#!/bin/bash
# Direct installer for Xray XHTTP + TLS 1.2
# Downloads and executes in /tmp without process substitution

set -e

echo "======================================================"
echo "Xray XHTTP + TLS 1.2 Direct Installer"
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
curl -sL https://github.com/cherdanalex/xray-xhttp-tls12-config/archive/2cb7597.tar.gz -o xray.tar.gz

echo "[2/4] Extracting files..."
tar xzf xray.tar.gz

# Find the extracted directory
EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "xray-xhttp-tls12-config-*" | head -1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Could not find extracted directory"
    ls -la
    exit 1
fi

echo "[3/4] Entering directory: $EXTRACTED_DIR"
cd "$EXTRACTED_DIR"

echo "[4/4] Setting permissions and running deployment..."
chmod +x scripts/*.sh
./scripts/deploy.sh

echo ""
echo "[5/5] Cleaning up..."
cd /
rm -rf "$TMP_DIR"

echo ""
echo "======================================================"
echo "Installation completed!"
echo "======================================================"
