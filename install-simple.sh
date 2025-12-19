#!/bin/bash

################################################################################
# Omada Kids VLAN Password Rotator - Simple Installation Script
# This script simply clones the repo and sets everything up
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${HOME}/omada-rotation"
GITHUB_REPO="https://github.com/codemanus/password-rotator.git"
SCRIPT_NAME="omada_rotation.sh"
CONFIG_NAME="omada_config.conf"

# Print colored messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (should not be)
if [[ $EUID -eq 0 ]]; then
    error "This script should not be run as root. Run as a regular user."
    exit 1
fi

echo ""
info "=========================================="
info "Omada Password Rotator - Simple Installer"
info "=========================================="
echo ""

# Step 1: Install dependencies
info "[1/6] Installing dependencies..."
if ! command -v git &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y git curl jq mailutils python3 python3-pip > /dev/null 2>&1
else
    # Check for other dependencies
    missing=()
    command -v curl &> /dev/null || missing+=("curl")
    command -v jq &> /dev/null || missing+=("jq")
    command -v mail &> /dev/null || missing+=("mailutils")
    command -v python3 &> /dev/null || missing+=("python3")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y "${missing[@]}" > /dev/null 2>&1
    fi
fi
success "Dependencies installed"

# Step 2: Create installation directory
info "[2/6] Creating installation directory..."
if [[ -d "$INSTALL_DIR" ]]; then
    warning "Directory already exists: $INSTALL_DIR"
    read -p "Remove and reinstall? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
    else
        error "Installation cancelled"
        exit 1
    fi
fi
mkdir -p "$INSTALL_DIR"
success "Directory created: $INSTALL_DIR"

# Step 3: Clone repository
info "[3/6] Cloning repository from GitHub..."
if git clone "$GITHUB_REPO" "$INSTALL_DIR" 2>&1; then
    success "Repository cloned"
else
    error "Failed to clone repository. Check your internet connection and try again."
    exit 1
fi

# Step 4: Verify required files
info "[4/6] Verifying files..."
if [[ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
    error "Required file not found: $SCRIPT_NAME"
    exit 1
fi

# Step 5: Set up config file
info "[5/6] Setting up configuration file..."
if [[ -f "$INSTALL_DIR/$CONFIG_NAME" ]]; then
    warning "Config file already exists. Keeping existing file."
elif [[ -f "$INSTALL_DIR/${CONFIG_NAME}.example" ]]; then
    cp "$INSTALL_DIR/${CONFIG_NAME}.example" "$INSTALL_DIR/$CONFIG_NAME"
    success "Created $CONFIG_NAME from template"
else
    error "Neither $CONFIG_NAME nor ${CONFIG_NAME}.example found in repository"
    exit 1
fi

# Step 6: Set permissions
info "[6/6] Setting file permissions..."
chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"
chmod 600 "$INSTALL_DIR/$CONFIG_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
success "Permissions set"

# Clean up .git directory (optional - keeps repo clean)
read -p "Remove .git directory to save space? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR/.git"
    info ".git directory removed"
fi

# Summary
echo ""
success "=========================================="
success "Installation Complete!"
success "=========================================="
echo ""
info "Installation directory: $INSTALL_DIR"
info "Script: $INSTALL_DIR/$SCRIPT_NAME"
info "Config: $INSTALL_DIR/$CONFIG_NAME"
echo ""
info "Next steps:"
echo "  1. Edit config file: nano $INSTALL_DIR/$CONFIG_NAME"
echo "  2. Test the script: cd $INSTALL_DIR && ./$SCRIPT_NAME"
echo "  3. Set up cron job: crontab -e"
echo "     Add: 0 6 * * * cd $INSTALL_DIR && TZ=America/New_York /bin/bash $INSTALL_DIR/$SCRIPT_NAME >> $INSTALL_DIR/cron.log 2>&1"
echo ""
warning "IMPORTANT: Configure all values in the config file before running!"
echo ""

