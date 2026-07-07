#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_SCRIPT="${SCRIPT_DIR%/ct}/raycast-relay.sh"

if [[ ! -f "${ROOT_SCRIPT}" ]]; then
  echo "Missing ${ROOT_SCRIPT}" >&2
  exit 1
fi

exec bash "${ROOT_SCRIPT}" "$@"
