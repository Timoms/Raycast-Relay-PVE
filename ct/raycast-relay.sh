#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Timoms
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/szcharlesji/raycast-relay

# ============================================================================
# APP CONFIGURATION
# ============================================================================
# These values are sent to build.func and define default container resources.
# Users can customize these during installation via the interactive prompts.
# ============================================================================

APP="Raycast Relay"
var_tags="${var_tags:-apirelay;raycast}"        # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-2}"                         # CPU cores: 1-4 typical
var_ram="${var_ram:-512}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-8}"                       # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                      # OS: debian, ubuntu, alpine
var_version="${var_version:-13}"                # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"       # 1=unprivileged (secure), 0=privileged (for Docker/Podman)
var_net=dhcp     # Automatic IP via DHCP
var_mtu=1500     # Standard Ethernet
var_ipv6_method=none
var_ssh=yes      # SSH server enabled
var_nesting=1    # Nested containers allowed, for systemd, Docker, Podman, etc.

APP_NAME="Raycast Relay"
APP_NAME_LINUX="raycast_relay"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
INSTALLER_REPO_BASE_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
LOCAL_INSTALLER_PATH=""
USE_LOCAL_INSTALLER="false"

function configure_installer_source() {
  local install_url="${INSTALLER_REPO_BASE_URL}/install/${var_install}.sh"
  LOCAL_INSTALLER_PATH="${PROJECT_ROOT}/install/${var_install}.sh"

  if [[ -f "${LOCAL_INSTALLER_PATH}" ]]; then
    USE_LOCAL_INSTALLER="true"
    msg_info "Using local installer: ${LOCAL_INSTALLER_PATH}"
    msg_ok "Local installer source configured"
    return
  fi

  if curl -fsSL "$install_url" >/dev/null 2>&1; then
    USE_LOCAL_INSTALLER="false"
    msg_info "Local installer missing, falling back to upstream installer"
    msg_ok "Upstream installer source configured"
    return
  fi

  msg_error "No installer source found."
  msg_error "Missing local file: ${LOCAL_INSTALLER_PATH}"
  msg_error "Missing upstream file: ${install_url}"
  exit 1
}

function curl() {
  local url="${@: -1}"
  if [[ "${USE_LOCAL_INSTALLER}" == "true" && "${url}" == "${INSTALLER_REPO_BASE_URL}/install/${var_install}.sh" ]]; then
    cat "${LOCAL_INSTALLER_PATH}"
    return 0
  fi
  command curl "$@"
}

# ============================================================================
# INITIALIZATION - These are required in all CT scripts
# ============================================================================
header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure
configure_installer_source

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/${APP_NAME_LINUX} ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Stop services before update
  msg_info "Stopping Service"
  systemctl stop ${APP_NAME_LINUX}
  msg_ok "Stopped Service"
  
  # Download and deploy new version
  CLEAN_INSTALL=1 
  $STD git clone https://github.com/szcharlesji/raycast-relay.git /opt/${APP_NAME_LINUX}
  # Run post-update commands (uncomment as needed)
  msg_info "Installing Dependencies"
  cd /opt/${APP_NAME_LINUX}/src
  $STD npm ci --production
  msg_ok "Installed Dependencies"
  
  # Restart service with new version
  msg_info "Starting Service"
  systemctl start ${APP_NAME_LINUX}
  msg_ok "Started Service"
  msg_ok "Updated successfully!"

  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e  "${INFO}${YW}Access ${APP_NAME} using the following URL:${CL}"
echo -e  "${GATEWAY}${BGN}http://${IP}:8788/health${CL}"
echo -e  "You can edit the .dev.vars file at /opt/${APP_NAME_LINUX}/.dev.vars to update your credentials and settings.${CL}"
echo -e  "Visit the official repository for more information:${CL}"
echo -e  "https://github.com/szcharlesji/raycast-relay${CL}"