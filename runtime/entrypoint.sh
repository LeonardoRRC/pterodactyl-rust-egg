#!/bin/bash
# ============================================================
#  pxsvc :: entrypoint.sh
#  Runtime for Rust services on Pterodactyl
#  Flow: env -> git -> toolchain -> cargo build -> tunnel -> run
# ============================================================
set -o pipefail

export PXSVC_DIR="/home/container/.pxsvc"
cd /home/container || exit 1

for _lib in common git rust cloudflare; do
    # shellcheck source=/dev/null
    [ -f "${PXSVC_DIR}/lib/${_lib}.sh" ] && . "${PXSVC_DIR}/lib/${_lib}.sh"
done

if ! command -v pxsvc_log >/dev/null 2>&1; then
    echo "[pxsvc] ERROR: libraries missing from ${PXSVC_DIR}/lib. Reinstall the server."
    exit 1
fi

pxsvc_env_setup
pxsvc_banner
pxsvc_git_sync
pxsvc_ensure_toolchain
pxsvc_build
pxsvc_cf_start
pxsvc_run
