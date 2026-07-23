#!/bin/bash
# ============================================================
#  pxsvc :: cloudflare.sh  ·  reverse proxy via Cloudflare Tunnel
#  Modes: quick (temporary URL) · token (dashboard token)
#         named (interactive login + tunnel and DNS creation)
# ============================================================

PXSVC_CF_DIR="/home/container/.cloudflared"
PXSVC_CF_LOG="/home/container/.pxsvc/logs/cloudflared.log"

pxsvc_cf_bin() {
    if [ -x "${PXSVC_DIR}/bin/cloudflared" ]; then
        PXSVC_CFD="${PXSVC_DIR}/bin/cloudflared"; return 0
    fi
    if command -v cloudflared >/dev/null 2>&1; then
        PXSVC_CFD="$(command -v cloudflared)"; return 0
    fi

    pxsvc_log "Downloading cloudflared..."
    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armhf) arch="arm" ;;
        *) arch="amd64" ;;
    esac
    mkdir -p "${PXSVC_DIR}/bin"
    if curl -fsSL -o "${PXSVC_DIR}/bin/cloudflared" \
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"; then
        chmod +x "${PXSVC_DIR}/bin/cloudflared"
        PXSVC_CFD="${PXSVC_DIR}/bin/cloudflared"
        return 0
    fi
    return 1
}

pxsvc_cf_tail() {
    ( tail -n 0 -F "${PXSVC_CF_LOG}" 2>/dev/null \
        | while IFS= read -r line; do echo -e "${C_DIM}[cloudflared]${C_RESET} ${line}"; done ) &
}

pxsvc_cf_box() {
    echo ""
    echo -e "${C_GREEN}  ══════════════════════════════════════════════════════${C_RESET}"
    echo -e "   $1"
    echo -e "   ${C_B}${C_GREEN}$2${C_RESET}"
    echo -e "${C_GREEN}  ══════════════════════════════════════════════════════${C_RESET}"
    echo ""
}

pxsvc_cf_start() {
    local mode="${CF_MODE:-off}"
    if ! pxsvc_bool "${CF_ENABLED}" || [ "${mode}" = "off" ]; then
        pxsvc_log "Cloudflare Tunnel disabled"
        return 0
    fi

    pxsvc_step "Cloudflare Tunnel · ${mode} mode"

    if ! pxsvc_cf_bin; then
        pxsvc_err "Could not obtain the cloudflared binary; the service will start without a tunnel"
        return 1
    fi

    mkdir -p "${PXSVC_CF_DIR}" "$(dirname "${PXSVC_CF_LOG}")"
    chmod 700 "${PXSVC_CF_DIR}" 2>/dev/null
    : > "${PXSVC_CF_LOG}"
    export TUNNEL_ORIGIN_CERT="${PXSVC_CF_DIR}/cert.pem"

    local svc="${CF_SERVICE_URL:-http://127.0.0.1:${SERVER_PORT}}"
    local -a globals=(--no-autoupdate --loglevel "${CF_LOGLEVEL:-info}" --logfile "${PXSVC_CF_LOG}")
    local -a runflags=()
    if [ -n "${CF_PROTOCOL}" ] && [ "${CF_PROTOCOL}" != "auto" ]; then
        runflags+=(--protocol "${CF_PROTOCOL}")
    fi

    case "${mode}" in
        quick)   pxsvc_cf_quick "${svc}" ;;
        token)   pxsvc_cf_token ;;
        named)   pxsvc_cf_named "${svc}" ;;
        *)       pxsvc_err "Unknown CF_MODE: ${mode}"; return 1 ;;
    esac
}

# ---------- MODE 1: quick tunnel (*.trycloudflare.com URL) ----------
pxsvc_cf_quick() {
    local svc="$1"
    pxsvc_log "Creating a temporary tunnel to ${svc}"
    "${PXSVC_CFD}" "${globals[@]}" tunnel "${runflags[@]}" --url "${svc}" >/dev/null 2>&1 &
    PXSVC_CF_PID=$!
    pxsvc_cf_tail

    local url="" i
    for i in $(seq 1 30); do
        url="$(grep -oE 'https://[-a-z0-9]+\.trycloudflare\.com' "${PXSVC_CF_LOG}" 2>/dev/null | head -n1)"
        [ -n "${url}" ] && break
        sleep 1
    done

    if [ -n "${url}" ]; then
        pxsvc_cf_box "Your service is published at:" "${url}"
        echo "${url}" > "${PXSVC_DIR}/logs/tunnel-url.txt"
    else
        pxsvc_warn "The temporary URL is not available yet; check the cloudflared log"
    fi
}

# ---------- MODE 2: dashboard token (recommended for production) ----------
pxsvc_cf_token() {
    if [ -z "${CF_TOKEN}" ]; then
        pxsvc_err "CF_MODE=token but CF_TOKEN is empty."
        pxsvc_err "Create it at: Cloudflare Zero Trust -> Networks -> Tunnels -> Create a tunnel -> copy the token."
        return 1
    fi
    pxsvc_log "Connecting the dashboard-managed tunnel"
    "${PXSVC_CFD}" "${globals[@]}" tunnel run "${runflags[@]}" --token "${CF_TOKEN}" >/dev/null 2>&1 &
    PXSVC_CF_PID=$!
    pxsvc_cf_tail
    [ -n "${CF_HOSTNAME}" ] && pxsvc_cf_box "Public (per the dashboard ingress rules):" "https://${CF_HOSTNAME}"
    pxsvc_ok "Tunnel started (PID ${PXSVC_CF_PID})"
}

# ---------- MODE 3: interactive login + named tunnel + DNS ----------
pxsvc_cf_named() {
    local svc="$1"
    local name="${CF_TUNNEL_NAME:-pxsvc-${P_SERVER_UUID:0:8}}"

    if [ ! -f "${TUNNEL_ORIGIN_CERT}" ]; then
        pxsvc_warn "No saved Cloudflare session. Starting authentication..."
        pxsvc_log "1) Copy the URL printed below and open it in your browser"
        pxsvc_log "2) Log in and authorize the domain you want to use"
        pxsvc_log "3) Startup will continue automatically once you are done"
        "${PXSVC_CFD}" tunnel login
        if [ ! -f "${TUNNEL_ORIGIN_CERT}" ]; then
            pxsvc_err "Login was not completed (no cert.pem generated). Restart the server to try again."
            return 1
        fi
        pxsvc_ok "Session saved to .cloudflared/cert.pem"
    fi

    if ! "${PXSVC_CFD}" tunnel info "${name}" >/dev/null 2>&1; then
        pxsvc_log "Creating tunnel '${name}'"
        "${PXSVC_CFD}" tunnel create "${name}" || { pxsvc_err "Could not create the tunnel"; return 1; }
    else
        pxsvc_log "Reusing existing tunnel '${name}'"
    fi

    local cred
    cred="$(ls -t "${PXSVC_CF_DIR}"/*.json 2>/dev/null | head -n1)"

    {
        echo "tunnel: ${name}"
        [ -n "${cred}" ] && echo "credentials-file: ${cred}"
        echo "ingress:"
        if [ -n "${CF_HOSTNAME}" ]; then
            echo "  - hostname: ${CF_HOSTNAME}"
            echo "    service: ${svc}"
            echo "  - service: http_status:404"
        else
            echo "  - service: ${svc}"
        fi
    } > "${PXSVC_CF_DIR}/config.yml"

    if [ -n "${CF_HOSTNAME}" ]; then
        pxsvc_log "Registering DNS ${CF_HOSTNAME} -> ${name}"
        "${PXSVC_CFD}" tunnel route dns --overwrite-dns "${name}" "${CF_HOSTNAME}" >/dev/null 2>&1 \
            || "${PXSVC_CFD}" tunnel route dns "${name}" "${CF_HOSTNAME}" >/dev/null 2>&1 \
            || pxsvc_warn "Could not create the DNS record (does it already point somewhere else?)"
    fi

    # Reusable token: written to disk, never printed in full to the console
    local tok
    tok="$("${PXSVC_CFD}" tunnel token "${name}" 2>/dev/null | tr -d '\r\n')"
    if [ -n "${tok}" ]; then
        printf '%s' "${tok}" > "${PXSVC_CF_DIR}/token.txt"
        chmod 600 "${PXSVC_CF_DIR}/token.txt" 2>/dev/null
        pxsvc_ok "Token generated and saved to .cloudflared/token.txt (${tok:0:6}...${tok: -6})"
        pxsvc_log "Download it from the file manager and paste it into CF_TOKEN + CF_MODE=token for login-free startups."
    fi

    "${PXSVC_CFD}" "${globals[@]}" --config "${PXSVC_CF_DIR}/config.yml" tunnel run "${runflags[@]}" "${name}" >/dev/null 2>&1 &
    PXSVC_CF_PID=$!
    pxsvc_cf_tail
    [ -n "${CF_HOSTNAME}" ] && pxsvc_cf_box "Your service is published at:" "https://${CF_HOSTNAME}"
    pxsvc_ok "Tunnel '${name}' started (PID ${PXSVC_CF_PID})"
}
