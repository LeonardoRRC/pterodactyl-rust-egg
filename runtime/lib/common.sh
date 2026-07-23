#!/bin/bash
# ============================================================
#  pxsvc :: common.sh  ·  shared helpers
# ============================================================

C_RESET='\033[0m'; C_B='\033[1m'; C_DIM='\033[2m'
C_BLUE='\033[38;5;39m'; C_GREEN='\033[38;5;42m'
C_YELLOW='\033[38;5;220m'; C_RED='\033[38;5;203m'; C_PURPLE='\033[38;5;141m'

pxsvc_log()  { echo -e "${C_BLUE}[pxsvc]${C_RESET} $*"; }
pxsvc_ok()   { echo -e "${C_GREEN}[pxsvc]${C_RESET} $*"; }
pxsvc_warn() { echo -e "${C_YELLOW}[pxsvc]${C_RESET} $*"; }
pxsvc_err()  { echo -e "${C_RED}[pxsvc]${C_RESET} $*"; }
pxsvc_step() { echo -e "\n${C_PURPLE}==>${C_RESET} ${C_B}$*${C_RESET}"; }
pxsvc_die()  { pxsvc_err "$*"; exit 1; }

# Treats 1/true/yes/on/enabled as true
pxsvc_bool() {
    case "$(echo "${1:-0}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on|enabled) return 0 ;;
        *) return 1 ;;
    esac
}

pxsvc_env_setup() {
    export HOME="/home/container"
    export USER="${USER:-container}"
    export CARGO_HOME="${CARGO_HOME:-/home/container/.cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-/home/container/.rustup}"
    export PATH="${CARGO_HOME}/bin:${PXSVC_DIR}/bin:${PATH}"
    export CARGO_TERM_COLOR="${CARGO_TERM_COLOR:-always}"
    export RUST_LOG="${RUST_LOG:-info}"
    export RUST_BACKTRACE="${RUST_BACKTRACE:-0}"
    export GIT_TERMINAL_PROMPT=0

    if [ -z "${INTERNAL_IP}" ]; then
        INTERNAL_IP="$(ip route get 1 2>/dev/null | awk '{print $(NF-2); exit}')"
        export INTERNAL_IP
    fi

    # Handy shortcuts for use inside APP_ARGS / CUSTOM_STARTUP
    export BIND_ADDR="0.0.0.0:${SERVER_PORT}"
    export PORT="${SERVER_PORT}"

    mkdir -p "${PXSVC_DIR}/logs" "${PXSVC_DIR}/bin"

    # User-defined extra variables: KEY=VALUE pairs separated by ';'
    if [ -n "${ENV_VARS}" ]; then
        local _pair _key _val
        while IFS= read -r _pair; do
            _pair="$(echo "${_pair}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [ -z "${_pair}" ] && continue
            case "${_pair}" in \#*) continue ;; esac
            case "${_pair}" in *=*) ;; *) continue ;; esac
            _key="${_pair%%=*}"
            _val="${_pair#*=}"
            export "${_key}=${_val}"
        done < <(echo "${ENV_VARS}" | tr ';' '\n')
    fi
}

pxsvc_banner() {
    echo -e "${C_PURPLE}"
    echo "  ┌──────────────────────────────────────────────┐"
    echo "  │   RUST SERVICE RUNTIME  ·  Pterodactyl Egg    │"
    echo "  └──────────────────────────────────────────────┘"
    echo -e "${C_RESET}"
    echo -e "  ${C_DIM}Repository :${C_RESET} ${GIT_REPO:-(local source)}"
    echo -e "  ${C_DIM}Branch     :${C_RESET} ${GIT_BRANCH:-main}"
    echo -e "  ${C_DIM}Toolchain  :${C_RESET} ${RUST_TOOLCHAIN:-default}${RUST_TARGET:+ (${RUST_TARGET})}"
    echo -e "  ${C_DIM}Profile    :${C_RESET} ${BUILD_PROFILE:-release}"
    echo -e "  ${C_DIM}Build      :${C_RESET} $(pxsvc_bool "${BUILD_ON_BOOT}" && echo 'yes' || echo 'no')"
    echo -e "  ${C_DIM}Port       :${C_RESET} ${SERVER_PORT}  (BIND_ADDR=${BIND_ADDR})"
    echo -e "  ${C_DIM}CF tunnel  :${C_RESET} $(pxsvc_bool "${CF_ENABLED}" && echo "${CF_MODE:-off}" || echo 'disabled')"
    echo ""
}

# Locates the compiled binary. Exports PXSVC_BIN on success.
pxsvc_resolve_binary() {
    local base="target"
    [ -n "${RUST_TARGET}" ] && base="target/${RUST_TARGET}"
    local dir="${base}/release"
    [ "${BUILD_PROFILE}" = "debug" ] && dir="${base}/debug"

    local name="${BINARY_NAME}"
    [ -z "${name}" ] && name="${CARGO_BIN}"
    if [ -z "${name}" ] && [ -f Cargo.toml ]; then
        name="$(grep -m1 -E '^\s*name\s*=' Cargo.toml | sed -E 's/.*=\s*"([^"]+)".*/\1/')"
    fi

    if [ -n "${name}" ] && [ -x "${dir}/${name}" ]; then
        export PXSVC_BIN="${dir}/${name}"
        return 0
    fi

    # Last resort: first executable in the output directory
    local found
    found="$(find "${dir}" -maxdepth 1 -type f -executable ! -name '*.d' ! -name '*.so' 2>/dev/null | head -n1)"
    if [ -n "${found}" ]; then
        export PXSVC_BIN="${found}"
        pxsvc_warn "Binary auto-detected: ${PXSVC_BIN}"
        return 0
    fi

    unset PXSVC_BIN
    return 1
}

pxsvc_run() {
    local cmd
    pxsvc_resolve_binary >/dev/null 2>&1

    if [ -n "${CUSTOM_STARTUP}" ]; then
        cmd="${CUSTOM_STARTUP}"
    else
        [ -n "${PXSVC_BIN}" ] || pxsvc_die "Binary not found. Set BINARY_NAME/CARGO_BIN, enable BUILD_ON_BOOT, or use CUSTOM_STARTUP."
        cmd="\"${PXSVC_BIN}\" ${APP_ARGS}"
    fi

    pxsvc_step "Starting service"
    echo -e "${C_DIM}container@pterodactyl:~$ ${cmd}${C_RESET}"
    echo "[pxsvc] service is running"
    exec bash -c "${cmd}"
}
