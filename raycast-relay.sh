#!/usr/bin/env bash
set -euo pipefail

APP_NAME="raycast-relay"
CTID="${CTID:-$(pvesh get /cluster/nextid)}"
HOSTNAME="${HOSTNAME:-raycast-relay}"
CORES="${CORES:-2}"
MEMORY_MB="${MEMORY_MB:-2048}"
DISK_GB="${DISK_GB:-8}"
BRIDGE="${BRIDGE:-vmbr0}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
ONBOOT="${ONBOOT:-1}" 

log() {
  printf '[%s] %s\n' "$APP_NAME" "$*"
}

fail() {
  printf '[%s] ERROR: %s\n' "$APP_NAME" "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run as root"
}

require_proxmox_host() {
  command -v pveversion >/dev/null 2>&1 || fail "This script must run on a Proxmox host"
}

ensure_tools() {
  apt-get update
  apt-get install -y curl ca-certificates jq
}

resolve_storage() {
  TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-$(pvesm status -content vztmpl | awk 'NR>1 {print $1; exit}') }"
  CONTAINER_STORAGE="${CONTAINER_STORAGE:-$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}') }"

  [[ -n "${TEMPLATE_STORAGE}" ]] || fail "No storage found with vztmpl content"
  [[ -n "${CONTAINER_STORAGE}" ]] || fail "No storage found with rootdir content"
}

resolve_template() {
  local arch
  arch="$(dpkg --print-architecture)"

  case "$arch" in
    amd64) arch_pattern="amd64" ;;
    arm64) arch_pattern="arm64" ;;
    *) fail "Unsupported architecture: ${arch}" ;;
  esac

  TEMPLATE="${TEMPLATE:-$(pveam available -section system | awk '{print $2}' | grep -E "^debian-13-standard_.*_${arch_pattern}\.tar\.(zst|xz|gz)$" | sort -V | tail -1)}"
  [[ -n "${TEMPLATE}" ]] || fail "No Debian 13 template found for ${arch_pattern}"

  if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -q "/${TEMPLATE}$"; then
    log "Downloading template ${TEMPLATE} to ${TEMPLATE_STORAGE}"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
  fi
}

check_ctid_free() {
  if pct status "$CTID" >/dev/null 2>&1 || qm status "$CTID" >/dev/null 2>&1; then
    fail "CTID ${CTID} is already in use"
  fi
}

create_container() {
  log "Creating LXC ${CTID}"
  pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    -hostname "$HOSTNAME" \
    -cores "$CORES" \
    -memory "$MEMORY_MB" \
    -rootfs "${CONTAINER_STORAGE}:${DISK_GB}" \
    -net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    -unprivileged "$UNPRIVILEGED" \
    -features "nesting=1,keyctl=1" \
    -onboot "$ONBOOT"
}

start_container() {
  log "Starting LXC ${CTID}"
  pct start "$CTID"

  local i
  for i in {1..30}; do
    if pct exec "$CTID" -- bash -lc 'command -v apt-get >/dev/null 2>&1'; then
      return 0
    fi
    sleep 1
  done

  fail "Container did not become ready in time"
}

install_inside_container() {
  local installer
  installer="$(mktemp /tmp/raycast-relay-install.XXXXXX.sh)"

  cat >"$installer" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="raycast-relay"
APP_DIR="/opt/${APP_NAME}"
ENV_FILE="${APP_DIR}/.dev.vars"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SERVICE_USER="${APP_NAME}"
SERVICE_GROUP="${APP_NAME}"
REPO_URL="https://github.com/szcharlesji/raycast-relay.git"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg git

node_major=0
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
fi
if [[ "$node_major" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

if ! getent group "${SERVICE_GROUP}" >/dev/null 2>&1; then
  groupadd --system "${SERVICE_GROUP}"
fi
if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --gid "${SERVICE_GROUP}" --home-dir "${APP_DIR}" --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only
elif [[ -e "${APP_DIR}" ]] && [[ -n "$(ls -A "${APP_DIR}" 2>/dev/null || true)" ]]; then
  echo "${APP_DIR} exists and is not empty" >&2
  exit 1
else
  git clone --depth 1 "${REPO_URL}" "${APP_DIR}"
fi

cd "${APP_DIR}"
npm install

if [[ ! -f "${ENV_FILE}" ]]; then
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
fi

chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "${APP_DIR}"

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
systemctl enable "${APP_NAME}.service"

if ! grep -q 'change-me' "${ENV_FILE}"; then
  systemctl restart "${APP_NAME}.service"
fi
EOS

  chmod +x "$installer"
  pct push "$CTID" "$installer" /root/raycast-relay-install.sh
  rm -f "$installer"

  log "Installing Raycast Relay inside LXC ${CTID}"
  pct exec "$CTID" -- bash -lc 'bash /root/raycast-relay-install.sh && rm -f /root/raycast-relay-install.sh'
}

container_ip() {
  pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'"
}

main() {
  require_root
  require_proxmox_host
  ensure_tools
  resolve_storage
  resolve_template
  check_ctid_free
  create_container
  start_container
  install_inside_container

  local ip
  ip="$(container_ip || true)"

  log "Done"
  echo "CTID: ${CTID}"
  echo "Host: ${HOSTNAME}"
  echo "Container IP: ${ip:-unknown}"
  echo "Raycast Relay endpoint: http://${ip:-<container-ip>}:8788/v1"
  echo "Env file in CT: /opt/raycast-relay/.dev.vars"
}

main "$@"
