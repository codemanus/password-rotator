#!/bin/bash

################################################################################
# Omada Kids VLAN Password Rotation Script
# Rotates password daily and sends email notification
# Designed for Raspberry Pi 3B+ running on cron
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/omada_config.conf"
LOG_FILE="${SCRIPT_DIR}/omada_rotation.log"
COOKIE_FILE="/tmp/omada-cookies-${USER}.txt"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    send_error_email "$1"
    exit 1
}

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    error_exit "Configuration file not found: $CONFIG_FILE"
fi

source "$CONFIG_FILE"

# Validate required variables
required_vars=(OMADA_URL USERNAME PASSWORD SITE_ID WLAN_ID SSID_ID SSID_NAME RATE_LIMIT_ID VLAN_ID EMAIL_TO)
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error_exit "Required variable $var is not set in config file"
    fi
done

# Generate kid-friendly passphrase password
generate_password() {
    # Define word lists - expanded for more variety
    local adjectives=(
        "green" "red" "blue" "yellow" "purple" "orange" "pink" "black" "white"
        "fast" "slow" "big" "small" "tiny" "huge" "loud" "quiet"
        "happy" "silly" "funny" "cool" "awesome" "super" "magic" "wild"
        "sweet" "sour" "hot" "cold" "warm" "frozen" "bright" "dark"
        "brave" "strong" "smart" "clever" "kind" "gentle" "fierce" "calm"
    )
    local nouns=(
        "tiger" "rocket" "panda" "dragon" "pizza" "nugget"
        "lion" "bear" "shark" "eagle" "wolf" "fox" "cat" "dog"
        "robot" "ninja" "pirate" "knight" "wizard" "superhero" "alien" "monster"
        "star" "moon" "sun" "rainbow" "cloud" "storm" "lightning" "thunder"
        "castle" "treasure" "crown" "sword" "shield" "gem" "crystal" "coin"
        "cookie" "cake" "candy" "icecream" "donut" "banana" "apple" "berry"
        "car" "truck" "plane" "boat" "train" "bike" "skateboard" "scooter"
        "ball" "toy" "game" "puzzle" "book" "comic" "movie" "show"
    )
    
    # Randomly select adjective and noun
    local adj_idx=$((RANDOM % ${#adjectives[@]}))
    local noun_idx=$((RANDOM % ${#nouns[@]}))
    
    local adjective="${adjectives[$adj_idx]}"
    local noun="${nouns[$noun_idx]}"
    
    # Capitalize first letter of each word
    adjective="${adjective^}"
    noun="${noun^}"
    
    # Generate random number between 10-99
    local random_num=$((10 + RANDOM % 90))
    
    # Format as Adjective-Noun-Number
    local password="${adjective}-${noun}-${random_num}"
    
    echo "$password"
}

# Send success email
send_success_email() {
    local new_password="$1"
    local subject="Kids WiFi Password - $(date '+%Y-%m-%d')"
    
    local body="Hi,

The Kids VLAN WiFi password has been automatically updated.

Network Name (SSID): ${SSID_NAME}
New Password: ${new_password}
Valid Until: $(date -v+1d '+%Y-%m-%d 6:00 AM EST' 2>/dev/null || date -d '+1 day' '+%Y-%m-%d 6:00 AM EST' 2>/dev/null || date '+%Y-%m-%d 6:00 AM EST')

This password will automatically change again tomorrow at 6:00 AM EST.

---
Automated message from Omada Password Rotator
Raspberry Pi Homelab"

    # Try system mail command first
    if command -v mail &> /dev/null; then
        echo "$body" | mail -s "$subject" "$EMAIL_TO"
        log "Success email sent to $EMAIL_TO"
        return 0
    elif command -v sendmail &> /dev/null; then
        printf "Subject: %s\nFrom: %s\nTo: %s\n\n%s" "$subject" "$EMAIL_FROM" "$EMAIL_TO" "$body" | sendmail -t
        log "Success email sent to $EMAIL_TO via sendmail"
        return 0
    # Try Python email helper if available
    elif [[ -f "${SCRIPT_DIR}/send_email.py" ]] && [[ -n "${GMAIL_USER:-}" ]] && [[ -n "${GMAIL_APP_PASSWORD:-}" ]]; then
        python3 "${SCRIPT_DIR}/send_email.py" "$GMAIL_USER" "$GMAIL_APP_PASSWORD" "$EMAIL_TO" "success" "${SSID_NAME}|${new_password}"
        if [[ $? -eq 0 ]]; then
            log "Success email sent to $EMAIL_TO via Python helper"
            return 0
        fi
    fi
    
    # No email method available
    log "WARNING: No mail command available. Email not sent."
    log "New password: $new_password"
    return 1
}

# Send error email
send_error_email() {
    local error_msg="$1"
    local subject="ERROR: Kids WiFi Password Rotation Failed"
    
    local body="Hi,

The automated Kids VLAN WiFi password rotation failed.

Error: ${error_msg}
Time: $(date '+%Y-%m-%d %H:%M:%S')

Please check the log file: ${LOG_FILE}

The current password remains active.

---
Automated message from Omada Password Rotator
Raspberry Pi Homelab"

    # Try system mail command first
    if command -v mail &> /dev/null; then
        echo "$body" | mail -s "$subject" "$EMAIL_TO"
    elif command -v sendmail &> /dev/null; then
        printf "Subject: %s\nFrom: %s\nTo: %s\n\n%s" "$subject" "$EMAIL_FROM" "$EMAIL_TO" "$body" | sendmail -t
    # Try Python email helper if available
    elif [[ -f "${SCRIPT_DIR}/send_email.py" ]] && [[ -n "${GMAIL_USER:-}" ]] && [[ -n "${GMAIL_APP_PASSWORD:-}" ]]; then
        python3 "${SCRIPT_DIR}/send_email.py" "$GMAIL_USER" "$GMAIL_APP_PASSWORD" "$EMAIL_TO" "error" "$error_msg"
    fi
}

# Authenticate to Omada Controller
authenticate() {
    log "Authenticating to Omada Controller at $OMADA_URL"
    
    # Get controller ID
    local controller_id
    local api_response
    api_response=$(curl -sk "${OMADA_URL}/api/info" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to connect to Omada Controller at $OMADA_URL/api/info: $api_response"
    fi
    
    controller_id=$(echo "$api_response" | jq -r '.result.omadacId' 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$controller_id" || "$controller_id" == "null" ]]; then
        error_exit "Failed to retrieve controller ID from $OMADA_URL/api/info. Response: $api_response"
    fi
    
    log "Controller ID: $controller_id"
    
    # Login and get token
    local login_response
    local curl_output
    curl_output=$(curl -sk -X POST \
        -c "$COOKIE_FILE" \
        -b "$COOKIE_FILE" \
        -H "Content-Type: application/json" \
        "${OMADA_URL}/${controller_id}/api/v2/login" \
        -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to connect to login endpoint: $curl_output"
    fi
    
    login_response="$curl_output"
    local token
    token=$(echo "$login_response" | jq -r '.result.token' 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$token" || "$token" == "null" ]]; then
        error_exit "Authentication failed. Check credentials. Response: $login_response"
    fi
    
    log "Authentication successful"
    
    # Return both controller_id and token
    echo "${controller_id}|${token}"
}

# Update SSID password
update_password() {
    local controller_id="$1"
    local token="$2"
    local new_password="$3"
    
    log "Updating password for SSID: $SSID_NAME"
    
    # Prepare the JSON payload
    local payload
    payload=$(cat <<EOF
{
  "name": "${SSID_NAME}",
  "band": 3,
  "guestNetEnable": false,
  "security": 3,
  "broadcast": true,
  "vlanEnable": true,
  "vlanId": ${VLAN_ID},
  "pskSetting": {
    "securityKey": "${new_password}",
    "encryptionPsk": 3,
    "versionPsk": 2,
    "gikRekeyPskEnable": false
  },
  "rateLimit": {
    "rateLimitId": "${RATE_LIMIT_ID}"
  },
  "ssidRateLimit": {
    "rateLimitId": "${RATE_LIMIT_ID}"
  },
  "wlanScheduleEnable": false,
  "rateAndBeaconCtrl": {
    "rate2gCtrlEnable": false,
    "rate5gCtrlEnable": false,
    "rate6gCtrlEnable": false
  },
  "macFilterEnable": false,
  "wlanId": "",
  "enable11r": false,
  "pmfMode": 3,
  "multiCastSetting": {
    "multiCastEnable": true,
    "arpCastEnable": false,
    "filterEnable": false,
    "ipv6CastEnable": true,
    "channelUtil": 100
  },
  "mloEnable": false
}
EOF
)
    
    # Make the API call
    local response
    local curl_output
    curl_output=$(curl -sk -X PATCH \
        -b "$COOKIE_FILE" \
        -H "Content-Type: application/json;charset=utf-8" \
        -H "Csrf-Token: ${token}" \
        -H "X-Requested-With: XMLHttpRequest" \
        "${OMADA_URL}/${controller_id}/api/v2/sites/${SITE_ID}/setting/wlans/${WLAN_ID}/ssids/${SSID_ID}" \
        --data-raw "$payload" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log "ERROR: curl request failed: $curl_output"
        return 1
    fi
    
    response="$curl_output"
    local error_code
    error_code=$(echo "$response" | jq -r '.errorCode' 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log "ERROR: Failed to parse API response: $response"
        return 1
    fi
    
    if [[ "$error_code" != "0" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.msg' 2>/dev/null || echo "Unknown error")
        log "ERROR: API call failed. Error code: $error_code, Message: $error_msg"
        return 1
    fi
    
    log "Password updated successfully"
    return 0
}

# Cleanup function
cleanup() {
    if [[ -f "$COOKIE_FILE" ]]; then
        rm -f "$COOKIE_FILE"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    log "========== Starting password rotation =========="
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it: sudo apt-get install jq"
    fi
    
    # Generate new password
    NEW_PASSWORD=$(generate_password)
    log "Generated new password"
    
    # Authenticate
    auth_result=$(authenticate)
    if [[ -z "$auth_result" ]]; then
        error_exit "Authentication returned empty result"
    fi
    
    IFS='|' read -r CONTROLLER_ID TOKEN <<< "$auth_result"
    
    if [[ -z "$CONTROLLER_ID" || -z "$TOKEN" ]]; then
        error_exit "Failed to parse authentication result. Expected format: controller_id|token"
    fi
    
    # Update password with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if update_password "$CONTROLLER_ID" "$TOKEN" "$NEW_PASSWORD"; then
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log "Retry $retry_count/$max_retries after 10 seconds..."
                sleep 10
            else
                error_exit "Failed after $max_retries attempts"
            fi
        fi
    done
    
    # Send success notification
    send_success_email "$NEW_PASSWORD"
    
    log "========== Password rotation completed successfully =========="
}

# Run main function
main