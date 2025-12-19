#!/bin/bash

################################################################################
# Omada Kids VLAN Password Rotator - Installation Script
# This script installs the password rotation system on a Raspberry Pi
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
GITHUB_REPO=""  # Will be auto-detected or prompted if needed
SCRIPT_NAME="omada_rotation.sh"
CONFIG_NAME="omada_config.conf"
CRON_TIME="6"  # 6 AM EST

# Default GitHub repo (can be overridden)
DEFAULT_GITHUB_REPO="https://github.com/codemanus/password-rotator.git"

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

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

# Progress tracking function
update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    echo -e "${BLUE}[${percentage}%]${NC} $1"
}

# Check if running as root (should not be)
check_root() {
    update_progress "Checking user permissions..."
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Run as a regular user."
        exit 1
    fi
}

# Check if running on Raspberry Pi (optional check)
check_raspberry_pi() {
    update_progress "Detecting system type..."
    if [[ -f /proc/device-tree/model ]]; then
        # Use tr to remove null bytes that cause warnings
        local model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo "")
        if [[ -n "$model" ]] && [[ "$model" == *"Raspberry Pi"* ]]; then
            info "Detected Raspberry Pi: $model"
            return 0
        fi
    fi
    warning "Could not detect Raspberry Pi. Continuing anyway..."
    return 0
}

# Update system packages
update_system() {
    update_progress "Updating system packages..."
    sudo apt-get update -qq
    success "System packages updated"
}

# Install required dependencies
install_dependencies() {
    update_progress "Installing required dependencies..."
    
    local packages=("curl" "jq" "mailutils" "python3" "python3-pip")
    local missing_packages=()
    
    # Check which packages are missing
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  ${package} "; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        info "Installing: ${missing_packages[*]}"
        sudo apt-get install -y "${missing_packages[@]}" > /dev/null 2>&1
        success "Dependencies installed"
    else
        success "All dependencies already installed"
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq installation failed. Please install manually: sudo apt-get install jq"
        exit 1
    fi
}

# Create installation directory
create_directory() {
    update_progress "Creating installation directory..."
    mkdir -p "$INSTALL_DIR"
    success "Directory created: $INSTALL_DIR"
}

# Detect if script is being run via curl/pipe
is_piped_input() {
    # Check if stdin is a pipe (not a terminal)
    if [[ ! -t 0 ]]; then
        return 0  # True - we're in a pipe
    fi
    
    # Check if BASH_SOURCE points to a device file (like /dev/fd/63) which indicates pipe
    if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" =~ ^/dev/ ]]; then
        return 0  # True - we're in a pipe
    fi
    
    # Check if script is in a temporary location (common with curl)
    if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" =~ ^/tmp/ ]]; then
        return 0  # True - likely from pipe
    fi
    
    return 1  # False - we're not in a pipe
}

# Extract GitHub repo URL from curl command or use default
detect_github_repo() {
    # Check if GITHUB_REPO is already set
    if [[ -n "$GITHUB_REPO" ]]; then
        echo "$GITHUB_REPO"
        return 0
    fi
    
    # Try to extract from environment or use default
    if [[ -n "${GITHUB_REPO_URL:-}" ]]; then
        echo "$GITHUB_REPO_URL"
    else
        echo "$DEFAULT_GITHUB_REPO"
    fi
}

# Download from GitHub or use local files
download_files() {
    update_progress "Downloading files..."
    
    # Check if we're running from a pipe (curl | bash)
    local running_from_pipe=false
    if is_piped_input; then
        running_from_pipe=true
        info "Detected installation via curl. Will clone from GitHub..."
    fi
    
    # Try multiple locations to find the files (only if not piped)
    local script_dir=""
    local current_dir="$(pwd)"
    local source_dir=""
    
    if [[ "$running_from_pipe" == false ]]; then
        # Get script directory (handle different execution methods)
        if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        else
            script_dir="$current_dir"
        fi
        
        # Check script's directory first
        if [[ -f "$script_dir/$SCRIPT_NAME" ]] && [[ -f "$script_dir/$CONFIG_NAME" ]]; then
            source_dir="$script_dir"
            info "Found files in script directory: $source_dir"
        # Check current working directory
        elif [[ -f "$current_dir/$SCRIPT_NAME" ]] && [[ -f "$current_dir/$CONFIG_NAME" ]]; then
            source_dir="$current_dir"
            info "Found files in current directory: $source_dir"
        # Check parent directory (in case script is in a subdirectory)
        elif [[ -f "$(dirname "$script_dir")/$SCRIPT_NAME" ]] && [[ -f "$(dirname "$script_dir")/$CONFIG_NAME" ]]; then
            source_dir="$(dirname "$script_dir")"
            info "Found files in parent directory: $source_dir"
        fi
        
        # If we found files locally, copy them
        if [[ -n "$source_dir" ]]; then
            info "Copying files from: $source_dir"
            cp "$source_dir/$SCRIPT_NAME" "$INSTALL_DIR/"
            cp "$source_dir/$CONFIG_NAME" "$INSTALL_DIR/"
            success "Files copied to installation directory"
            return 0
        fi
    fi
    
    # If files not found locally, automatically try GitHub
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install it: sudo apt-get install git"
        exit 1
    fi
    
    # Auto-detect or get GitHub repo URL
    # If files aren't found locally, always try GitHub
    if [[ -z "$GITHUB_REPO" ]]; then
        # Check if we're in non-interactive mode (pipe or no terminal)
        if [[ "$running_from_pipe" == true ]] || [[ ! -t 0 ]] || [[ -z "${PS1:-}" ]]; then
            # Non-interactive mode (pipe) - use default automatically
            GITHUB_REPO=$(detect_github_repo)
            info "Local files not found. Automatically using GitHub repository: $GITHUB_REPO"
        else
            # Interactive mode - prompt user
            echo ""
            info "Local files not found. Will clone from GitHub."
            read -p "GitHub repository URL (press Enter for default: $DEFAULT_GITHUB_REPO): " GITHUB_REPO
            if [[ -z "$GITHUB_REPO" ]]; then
                GITHUB_REPO="$DEFAULT_GITHUB_REPO"
            fi
        fi
    fi
    
    # Ensure we have a repo URL (fallback to default if somehow still empty)
    if [[ -z "$GITHUB_REPO" ]]; then
        GITHUB_REPO="$DEFAULT_GITHUB_REPO"
        info "Using default GitHub repository: $GITHUB_REPO"
    fi
    
    # Clone from GitHub (this will always execute if we get here)
    info "Cloning from GitHub: $GITHUB_REPO"
    
    # Create a temporary directory for cloning
    local temp_clone_dir="${INSTALL_DIR}.tmp"
    if [[ -d "$temp_clone_dir" ]]; then
        rm -rf "$temp_clone_dir"
    fi
    
    if git clone "$GITHUB_REPO" "$temp_clone_dir" 2>&1; then
        success "Repository cloned"
        
        # Copy files from cloned repo to install directory
        if [[ -f "$temp_clone_dir/$SCRIPT_NAME" ]]; then
            cp "$temp_clone_dir/$SCRIPT_NAME" "$INSTALL_DIR/"
            success "Copied $SCRIPT_NAME"
        else
            error "Script file not found in repository: $SCRIPT_NAME"
            error "Please ensure the repository contains $SCRIPT_NAME"
            rm -rf "$temp_clone_dir"
            exit 1
        fi
        
        # Copy config file or template
        if [[ -f "$temp_clone_dir/$CONFIG_NAME" ]]; then
            cp "$temp_clone_dir/$CONFIG_NAME" "$INSTALL_DIR/"
            success "Copied $CONFIG_NAME"
        elif [[ -f "$temp_clone_dir/${CONFIG_NAME}.example" ]]; then
            # Copy the example file to the install directory (will be renamed to CONFIG_NAME in create_config_template)
            cp "$temp_clone_dir/${CONFIG_NAME}.example" "$INSTALL_DIR/${CONFIG_NAME}.example"
            success "Copied ${CONFIG_NAME}.example"
        else
            warning "Config file or template not found in repository. Will create basic template."
        fi
        
        # Clean up temp directory
        rm -rf "$temp_clone_dir"
        return 0
    else
        error "Failed to clone from GitHub. Please check the URL and try again."
        error "Repository URL: $GITHUB_REPO"
        rm -rf "$temp_clone_dir" 2>/dev/null
        exit 1
    fi
}

# Set file permissions
set_permissions() {
    update_progress "Setting file permissions..."
    
    # Set permissions for script (must exist)
    if [[ -f "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        chmod 700 "$INSTALL_DIR/$SCRIPT_NAME"
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        success "Script permissions set"
    else
        error "Script file not found: $INSTALL_DIR/$SCRIPT_NAME"
        exit 1
    fi
    
    # Set permissions for config (may not exist yet if template needs to be created)
    if [[ -f "$INSTALL_DIR/$CONFIG_NAME" ]]; then
        chmod 600 "$INSTALL_DIR/$CONFIG_NAME"
        success "Config permissions set"
    else
        info "Config file not found yet (will be created as template)"
    fi
}

# Create template config if it doesn't exist
create_config_template() {
    update_progress "Setting up configuration file..."
    if [[ ! -f "$INSTALL_DIR/$CONFIG_NAME" ]]; then
        # Try to find template in the install directory (from repo)
        if [[ -f "$INSTALL_DIR/${CONFIG_NAME}.example" ]]; then
            cp "$INSTALL_DIR/${CONFIG_NAME}.example" "$INSTALL_DIR/$CONFIG_NAME"
            # Remove the .example file since we've created the actual config
            rm -f "$INSTALL_DIR/${CONFIG_NAME}.example"
            success "Created $CONFIG_NAME from template"
        else
            warning "Config template not found. Creating basic template..."
            cat > "$INSTALL_DIR/$CONFIG_NAME" << 'EOF'
################################################################################
# Omada Controller Configuration
# Keep this file secure - it contains credentials!
################################################################################

# Omada Controller Settings
# For OC200, use: https://192.168.x.x (your OC200 IP)
OMADA_URL="https://192.168.0.2"

# Omada Controller Credentials
USERNAME="your-username"
PASSWORD="your-password"

# Site Configuration
# Get these values from browser Developer Tools (see setup guide)
SITE_ID="your-site-id"
WLAN_ID="your-wlan-id"
SSID_ID="your-ssid-id"
SSID_NAME="Your-SSID-Name"
RATE_LIMIT_ID="your-rate-limit-id"

# VLAN Configuration
VLAN_ID=20

# Email Configuration
EMAIL_TO="your-email@example.com"
EMAIL_FROM="your-email@example.com"

# Optional: Gmail SMTP Configuration (for Python email helper)
# Only needed if system mail is not configured
# GMAIL_USER="your_gmail@gmail.com"
# GMAIL_APP_PASSWORD="your_16_char_app_password"
EOF
            success "Basic template config file created"
        fi
        chmod 600 "$INSTALL_DIR/$CONFIG_NAME"
    else
        info "Config file already exists"
    fi
}

# Configure the installation
configure_installation() {
    update_progress "Configuring installation..."
    echo ""
    warning "You need to edit the config file with your Omada Controller settings."
    echo ""
    read -p "Would you like to edit the config file now? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v nano &> /dev/null; then
            nano "$INSTALL_DIR/$CONFIG_NAME"
        elif command -v vi &> /dev/null; then
            vi "$INSTALL_DIR/$CONFIG_NAME"
        else
            warning "No editor found. Please edit manually: $INSTALL_DIR/$CONFIG_NAME"
        fi
    else
        info "You can edit the config file later:"
        info "  nano $INSTALL_DIR/$CONFIG_NAME"
    fi
}

# Test the script
test_script() {
    update_progress "Testing script installation..."
    
    if [[ ! -x "$INSTALL_DIR/$SCRIPT_NAME" ]]; then
        error "Script is not executable!"
        return 1
    fi
    
    # Check if config has placeholder values
    if grep -q "your-" "$INSTALL_DIR/$CONFIG_NAME" 2>/dev/null; then
        warning "Config file still contains placeholder values. Please configure before running."
        return 1
    fi
    
    success "Script is ready (but not tested with actual API call)"
    return 0
}

# Setup cron job
setup_cron() {
    update_progress "Setting up cron job..."
    
    local cron_command="cd $INSTALL_DIR && TZ=America/New_York /bin/bash $INSTALL_DIR/$SCRIPT_NAME >> $INSTALL_DIR/cron.log 2>&1"
    local cron_entry="0 $CRON_TIME * * * $cron_command"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
        warning "Cron job already exists. Skipping..."
        return 0
    fi
    
    # Add cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    success "Cron job added (runs daily at $CRON_TIME AM EST)"
    info "To view cron jobs: crontab -l"
    info "To edit cron jobs: crontab -e"
}

# Print installation summary
print_summary() {
    update_progress "Finalizing installation..."
    echo ""
    success "=========================================="
    success "Installation Complete! (100%)"
    success "=========================================="
    echo ""
    info "Installation directory: $INSTALL_DIR"
    info "Script: $INSTALL_DIR/$SCRIPT_NAME"
    info "Config: $INSTALL_DIR/$CONFIG_NAME"
    info "Log file: $INSTALL_DIR/omada_rotation.log"
    echo ""
    info "Next steps:"
    echo "  1. Edit config file: nano $INSTALL_DIR/$CONFIG_NAME"
    echo "  2. Test the script: cd $INSTALL_DIR && ./$SCRIPT_NAME"
    echo "  3. Check the log: cat $INSTALL_DIR/omada_rotation.log"
    echo "  4. Verify cron job: crontab -l"
    echo ""
    warning "IMPORTANT: Make sure to configure all values in the config file!"
    echo ""
}

# Main installation function
main() {
    # Initialize progress tracking
    CURRENT_STEP=0
    
    echo ""
    info "=========================================="
    info "Omada Password Rotator - Installer"
    info "=========================================="
    echo ""
    
    check_root
    check_raspberry_pi
    update_system
    install_dependencies
    create_directory
    download_files
    create_config_template
    set_permissions
    configure_installation
    test_script
    setup_cron
    print_summary
}

# Run main function
main

