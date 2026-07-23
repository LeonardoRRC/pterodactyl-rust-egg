#!/bin/bash
# =====================================================================
#  Rust Service · Pterodactyl install script
#  Container: ghcr.io/parkervcp/installers:debian
#  Do NOT run this on the host: Wings executes it inside a container.
# =====================================================================

apt-get update -y >/dev/null 2>&1
apt-get install -y --no-install-recommends \
    ca-certificates curl wget git jq tar unzip xz-utils file >/dev/null 2>&1

export HOME=/mnt/server
mkdir -p /mnt/server/.pxsvc/bin /mnt/server/.pxsvc/lib /mnt/server/.pxsvc/logs
cd /mnt/server || exit 1

echo "==> Installing the pxsvc runtime into /mnt/server/.pxsvc"

# ---------------------------------------------------------------------
# 1. Runtime scripts
# ---------------------------------------------------------------------
cat > /mnt/server/.pxsvc/entrypoint.sh <<'PXSVC_EOF_ENTRYPOINT'
@@ENTRYPOINT@@
PXSVC_EOF_ENTRYPOINT

cat > /mnt/server/.pxsvc/lib/common.sh <<'PXSVC_EOF_COMMON'
@@COMMON@@
PXSVC_EOF_COMMON

cat > /mnt/server/.pxsvc/lib/git.sh <<'PXSVC_EOF_GIT'
@@GIT@@
PXSVC_EOF_GIT

cat > /mnt/server/.pxsvc/lib/rust.sh <<'PXSVC_EOF_RUST'
@@RUST@@
PXSVC_EOF_RUST

cat > /mnt/server/.pxsvc/lib/cloudflare.sh <<'PXSVC_EOF_CF'
@@CLOUDFLARE@@
PXSVC_EOF_CF

chmod +x /mnt/server/.pxsvc/entrypoint.sh /mnt/server/.pxsvc/lib/*.sh

# ---------------------------------------------------------------------
# 2. cloudflared
# ---------------------------------------------------------------------
case "$(uname -m)" in
    x86_64|amd64) CF_ARCH="amd64" ;;
    aarch64|arm64) CF_ARCH="arm64" ;;
    armv7l|armhf) CF_ARCH="arm" ;;
    *) CF_ARCH="amd64" ;;
esac
echo "==> Downloading cloudflared (${CF_ARCH})"
if curl -fsSL -o /mnt/server/.pxsvc/bin/cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"; then
    chmod +x /mnt/server/.pxsvc/bin/cloudflared
    echo "    cloudflared $(/mnt/server/.pxsvc/bin/cloudflared --version 2>/dev/null | head -n1)"
else
    echo "    [warning] cloudflared could not be downloaded; it will be retried on first boot"
fi

# ---------------------------------------------------------------------
# 3. Source code
# ---------------------------------------------------------------------
if [ -n "${GIT_REPO}" ]; then
    BRANCH="${GIT_BRANCH:-main}"
    AUTH_URL="${GIT_REPO}"
    if [ -n "${GIT_USER}" ] && [ -n "${GIT_TOKEN}" ]; then
        AUTH_URL=$(echo "${GIT_REPO}" | sed -E "s#^(https?://)#\1${GIT_USER}:${GIT_TOKEN}@#")
    elif [ -n "${GIT_TOKEN}" ]; then
        AUTH_URL=$(echo "${GIT_REPO}" | sed -E "s#^(https?://)#\1oauth2:${GIT_TOKEN}@#")
    fi
    export GIT_TERMINAL_PROMPT=0
    git config --global --add safe.directory /mnt/server >/dev/null 2>&1
    echo "==> Fetching ${GIT_REPO} (branch ${BRANCH})"
    if [ ! -d /mnt/server/.git ]; then
        git init -q /mnt/server
        git -C /mnt/server remote add origin "${AUTH_URL}" 2>/dev/null \
            || git -C /mnt/server remote set-url origin "${AUTH_URL}"
    else
        git -C /mnt/server remote set-url origin "${AUTH_URL}"
    fi
    if git -C /mnt/server fetch --depth 1 origin "${BRANCH}"; then
        git -C /mnt/server checkout -f -B "${BRANCH}" FETCH_HEAD >/dev/null 2>&1
        [ -f /mnt/server/.gitmodules ] && git -C /mnt/server submodule update --init --recursive --depth 1 >/dev/null 2>&1
        echo "    OK: $(git -C /mnt/server log -1 --pretty='%h %s' 2>/dev/null)"
    else
        echo "    [warning] could not fetch the repository (URL/branch/token?)"
    fi
    git -C /mnt/server remote set-url origin "${GIT_REPO}" 2>/dev/null
else
    echo "==> GIT_REPO is empty: upload your project through the file manager"
    if [ ! -f /mnt/server/Cargo.toml ]; then
        mkdir -p /mnt/server/src
        cat > /mnt/server/Cargo.toml <<'PXSVC_EOF_CARGO'
[package]
name = "my-service"
version = "0.1.0"
edition = "2021"

[dependencies]
PXSVC_EOF_CARGO
        cat > /mnt/server/src/main.rs <<'PXSVC_EOF_MAIN'
use std::io::{Read, Write};
use std::net::TcpListener;

fn main() -> std::io::Result<()> {
    let port = std::env::var("SERVER_PORT").unwrap_or_else(|_| "8080".into());
    let addr = format!("0.0.0.0:{port}");
    let listener = TcpListener::bind(&addr)?;
    println!("Example service listening on http://{addr}");

    for stream in listener.incoming() {
        let mut stream = stream?;
        let mut buf = [0u8; 1024];
        let _ = stream.read(&mut buf);
        let body = "Rust Service Egg: everything works.";
        let resp = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        );
        let _ = stream.write_all(resp.as_bytes());
    }
    Ok(())
}
PXSVC_EOF_MAIN
        echo "    Example project created (Cargo.toml + src/main.rs)"
    fi
fi

# ---------------------------------------------------------------------
# 4. Optional rustup inside the server volume
# ---------------------------------------------------------------------
if [ "${INSTALL_RUSTUP}" = "1" ] || [ "${INSTALL_RUSTUP}" = "true" ]; then
    echo "==> Installing rustup into the server volume"
    export RUSTUP_HOME=/mnt/server/.rustup
    export CARGO_HOME=/mnt/server/.cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --profile minimal \
                  --default-toolchain "${RUST_TOOLCHAIN:-stable}" \
        || echo "    [warning] rustup installation failed"
fi

mkdir -p /mnt/server/.cargo
[ -f /mnt/server/.cargo/config.toml ] || cat > /mnt/server/.cargo/config.toml <<'PXSVC_EOF_CARGOCFG'
[net]
retry = 3

[term]
color = "always"
PXSVC_EOF_CARGOCFG

echo ""
echo "================================================"
echo "  Installation complete"
echo "  Runtime : /home/container/.pxsvc"
echo "  Startup : bash .pxsvc/entrypoint.sh"
echo "================================================"
