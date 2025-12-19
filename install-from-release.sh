#!/bin/bash

################################################################################
# Omada Kids VLAN Password Rotator - Install from Release Package
# Downloads a release tarball and extracts it
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="${HOME}/omada-rotation"
RELEASE_URL="https://github.com/codemanus/password-rotator/releases/latest/download/password-rotator.tar.gz"

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
info "=========================================="
info "Omada Password Rotator - Release Installer"
info "=========================================="
echo ""

# Check dependencies
info "[1/5] Checking dependencies..."
missing=()
command -v curl &> /dev/null || missing+=("curl")
command -v jq &> /dev/null || missing+=("jq")
command -v mail &> /dev/null || missing+=("mailutils")
command -v python3 &> /dev/null || missing+=("python3")

if [[ ${#missing[@]} -gt 0 ]]; then
    info "Installing: ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}" > /dev/null 2>&1
fi
success "Dependencies ready"

# Create directory
info "[2/5] Creating installation directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
success "Directory ready"

# Download release
info "[3/5] Downloading release package..."
if curl -fsSL "$RELEASE_URL" -o /tmp/password-rotator.tar.gz; then
    success "Downloaded release package"
else
    error "Failed to download release. Check your internet connection."
    exit 1
fi

# Extract
info "[4/5] Extracting files..."
tar -xzf /tmp/password-rotator.tar.gz -C "$INSTALL_DIR"
rm /tmp/password-rotator.tar.gz
success "Files extracted"

# Set permissions
info "[5/5] Setting permissions..."
chmod 700 "$INSTALL_DIR/omada_rotation.sh"
chmod 600 "$INSTALL_DIR/omada_config.conf"
chmod +x "$INSTALL_DIR/omada_rotation.sh"
success "Permissions set"

echo ""
success "=========================================="
success "Installation Complete!"
success "=========================================="
echo ""
info "Installation directory: $INSTALL_DIR"
echo ""
info "Next steps:"
echo "  1. Edit config: nano $INSTALL_DIR/omada_config.conf"
echo "  2. Test: cd $INSTALL_DIR && ./omada_rotation.sh"
echo "  3. Set up cron: crontab -e"
echo ""

