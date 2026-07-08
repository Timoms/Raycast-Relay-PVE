#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Timoms
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/szcharlesji/raycast-relay

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# =============================================================================
# DOWNLOAD & DEPLOY APPLICATION
# =============================================================================

APP_NAME="Raycast Relay"
APP_NAME_LINUX="raycast_relay"

msg_info "Installing Dependencies"
$STD apt install -y openssl git
msg_ok "Installed Dependencies"

# --- Setup runtimes/databases ---
NODE_VERSION="22" NODE_MODULE="pnpm" setup_nodejs  # Installs pnpm
get_lxc_ip

# --- Download and install app ---
$STD git clone https://github.com/szcharlesji/raycast-relay.git /opt/${APP_NAME_LINUX}

msg_info "Setting up ${APP_NAME} dependencies"
cd /opt/${APP_NAME_LINUX}/src
# Install application dependencies:
$STD npm ci --production
msg_ok "Setup ${APP_NAME} dependencies successfully"

# =============================================================================
# CONFIGURATION
# =============================================================================

msg_info "Configuring ${APP_NAME}"
cd /opt/${APP_NAME_LINUX}/src

msg_info "This script needs you to capture your Raycast credentials from the Raycast app on your Mac. Follow the instructions in the official repo to get your Bearer Token, Device ID, and AID."

RAYCAST_BEARER_TOKEN="CHANGE_ME"
RAYCAST_DEVICE_ID="CHANGE_ME"
RAYCAST_AID="CHANGE_ME"
SIG_SECRET="CHANGE_ME"
API_KEY=$($STD openssl rand -hex 32)
PORT="8788"

if prompt_confirm "Do you want to configure Raycast credentials now? You can always update them later in the .dev.vars file." "y" 30; then
  RAYCAST_BEARER_TOKEN=$(prompt_input_required "Enter API token:" "CHANGE_ME" 120 "var_api_token")
  RAYCAST_DEVICE_ID=$(prompt_input_required "Enter Device ID:" "CHANGE_ME" 120 "var_device_id")
  RAYCAST_AID=$(prompt_input_required "Enter AID:" "CHANGE_ME" 120 "var_aid")
  SIG_SECRET=$(prompt_input_required "Enter Signature Secret:" "CHANGE_ME" 120 "var_sig_secret")
fi

API_KEY=$(prompt_input_required "Enter Local API Key or use the generated one (openssl rand -hex 32):" "$API_KEY" 120 "var_api_key")
INCLUDE_PREMIUM=$(prompt_input "Include premium models? (y/n)" "n" 30)
INCLUDE_DEPRECATED=$(prompt_input "Include deprecated models? (y/n)" "n" 30)

if [[ "$INCLUDE_PREMIUM" == "y" ]]; then
  INCLUDE_PREMIUM=true
else
  INCLUDE_PREMIUM=false
fi

if [[ "$INCLUDE_DEPRECATED" == "y" ]]; then
  INCLUDE_DEPRECATED=true
else
  INCLUDE_DEPRECATED=false
fi

# Create .dev.vars:
cat <<EOF >/opt/${APP_NAME_LINUX}/.dev.vars
RAYCAST_BEARER_TOKEN=$RAYCAST_BEARER_TOKEN
RAYCAST_DEVICE_ID=$RAYCAST_DEVICE_ID
RAYCAST_AID=$RAYCAST_AID
SIG_SECRET=$SIG_SECRET
API_KEY=$API_KEY
RAYCAST_USER_AGENT=Raycast/1.104.20 (macOS Version 26.5.1 (Build 25F80))
RAYCAST_EXPERIMENTAL=chatBranching, mcpHTTPServer

# Optional model-list filters:
# INCLUDE_PREMIUM=$INCLUDE_PREMIUM
# INCLUDE_DEPRECATED=$INCLUDE_DEPRECATED
EOF

msg_ok "Configured ${APP_NAME}"

# =============================================================================
# CREATE SYSTEMD SERVICE
# =============================================================================

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/${APP_NAME_LINUX}.service
[Unit]
Description=${APP_NAME} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/${APP_NAME_LINUX}/src
ExecStart=/usr/bin/node /opt/${APP_NAME_LINUX}/src/node-server.mjs --port ${PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now ${APP_NAME_LINUX}
msg_ok "Started and enabled ${APP_NAME} service"

# =============================================================================
# CLEANUP & FINALIZATION
# =============================================================================


motd_ssh
customize
cleanup_lxc
