#!/bin/bash
# Quick installer that bypasses GitHub cache

echo "Downloading and running Xray XHTTP deployment script..."
echo "This version bypasses GitHub's cache to ensure you get the latest version."
echo ""

# Download and run from specific commit
bash <(curl -fsSL https://raw.githubusercontent.com/cherdanalex/xray-xhttp-tls12-config/de49da8/scripts/deploy.sh)
