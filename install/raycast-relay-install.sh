#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/szcharlesji/raycast-relay

APP="Raycast Relay"
NSAPP="raycast-relay"
APP_DIR="/opt/${NSAPP}"
SERVICE_NAME="${NSAPP}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="${APP_DIR}/.dev.vars"
REPO_URL="https://github.com/szcharlesji/raycast-relay.git"
NODE_MIN_MAJOR=22
SERVICE_USER="${NSAPP}"
SERVICE_GROUP="${NSAPP}"

msg_info() {
  echo -e "[INFO] $*"
}

msg_ok() {
  echo -e "[OK] $*"
}

msg_warn() {
  echo -e "[WARN] $*"
}

msg_error() {
  echo -e "[ERROR] $*" >&2
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "Script must be run as root"
    exit 1
  fi
}

check_not_proxmox_host() {
  if command -v pveversion >/dev/null 2>&1; then
    msg_error "Refusing to install on the Proxmox host directly. Use the CT script to deploy into a new LXC container."
    exit 1
  fi
}

ensure_prereqs() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg git
}

ensure_node() {
  local node_major=0

  if command -v node >/dev/null 2>&1; then
    node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  fi

  if [[ "$node_major" -ge "$NODE_MIN_MAJOR" ]]; then
    msg_ok "Node.js ${node_major} is already installed"
    return 0
  fi

  msg_info "Installing Node.js ${NODE_MIN_MAJOR}"
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  msg_ok "Installed Node.js ${NODE_MIN_MAJOR}"
}

ensure_service_user() {
  if ! getent group "${SERVICE_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${SERVICE_GROUP}"
  fi

  if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
    useradd \
      --system \
      --gid "${SERVICE_GROUP}" \
      --home-dir "${APP_DIR}" \
      --shell /usr/sbin/nologin \
      "${SERVICE_USER}"
  fi
}

deploy_app() {
  if [[ -d "${APP_DIR}/.git" ]]; then
    msg_info "Updating existing checkout in ${APP_DIR}"
    git -C "${APP_DIR}" pull --ff-only
  elif [[ -e "${APP_DIR}" ]] && [[ -n "$(ls -A "${APP_DIR}" 2>/dev/null || true)" ]]; then
    msg_error "${APP_DIR} exists and is not an empty git checkout. Remove or move it first."
    exit 1
  else
    msg_info "Cloning ${APP} into ${APP_DIR}"
    git clone --depth 1 "${REPO_URL}" "${APP_DIR}"
  fi

  chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${APP_DIR}"
}

install_dependencies() {
  msg_info "Installing Node dependencies"
  cd "${APP_DIR}"
  npm install
}

write_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    msg_ok "Keeping existing env file at ${ENV_FILE}"
    return 0
  fi

  msg_info "Creating env file template at ${ENV_FILE}"
  cat >"${ENV_FILE}" <<'EOF'
RAYCAST_BEARER_TOKEN=change-me
RAYCAST_DEVICE_ID=change-me
RAYCAST_AID=change-me
SIG_SECRET=change-me
API_KEY=change-me
HOST=0.0.0.0
PORT=8788
RAYCAST_USER_AGENT=Raycast/1.104.20 (macOS Version 26.5.1 (Build 25F80))
RAYCAST_EXPERIMENTAL=chatBranching, mcpHTTPServer
# INCLUDE_PREMIUM=false
# INCLUDE_DEPRECATED=false
EOF
  chmod 600 "${ENV_FILE}"
  msg_ok "Created env file template"
}

write_service_file() {
  msg_info "Creating systemd service"
  cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=Raycast Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/node ${APP_DIR}/src/node-server.mjs
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}.service"

  if grep -q 'change-me' "${ENV_FILE}"; then
    msg_warn "Service enabled, but not started because ${ENV_FILE} still contains placeholder values"
    return 0
  fi

  systemctl restart "${SERVICE_NAME}.service"
  msg_ok "Created service"
}

print_summary() {
  echo ""
  echo "Installation complete"
  echo "App directory: ${APP_DIR}"
  echo "Env file: ${ENV_FILE}"
  echo "Service: ${SERVICE_NAME}.service"
  echo "Base URL: http://<host>:8788/v1"
  echo ""
  echo "Edit ${ENV_FILE} with your Raycast credentials, then run:"
  echo "  systemctl restart ${SERVICE_NAME}.service"
}

start() {
  check_root
  check_not_proxmox_host
  ensure_prereqs
  ensure_node
  ensure_service_user
  deploy_app
  install_dependencies
  write_env_file
  write_service_file
  print_summary
}

start "$@"
