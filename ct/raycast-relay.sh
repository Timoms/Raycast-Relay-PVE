#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/szcharlesji/raycast-relay

APP="Raycast Relay"
var_tags="${var_tags:-ai;proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/raycast-relay ]]; then
    msg_error "No ${APP} installation found"
    exit
  fi

  msg_info "Updating Raycast Relay"
  cd /opt/raycast-relay
  $STD git pull --ff-only
  $STD npm install

  if [[ -f /etc/systemd/system/raycast-relay.service ]]; then
    systemctl restart raycast-relay
  fi

  msg_ok "Updated successfully"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}The service listens on:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8788/v1${CL}"
