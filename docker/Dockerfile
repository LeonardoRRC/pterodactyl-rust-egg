# =====================================================================
#  Recommended image for the "Rust Service" egg
#  Includes: Rust toolchain + linker + OpenSSL + git + cloudflared
#  Build: docker build -t ghcr.io/YOUR_USER/pterodactyl-rust-service:latest .
#  Push : docker push ghcr.io/YOUR_USER/pterodactyl-rust-service:latest
# =====================================================================
FROM rust:1-bookworm

LABEL org.opencontainers.image.description="Rust service runtime for Pterodactyl (cargo + cloudflared)"

RUN apt-get update -y \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git jq iproute2 tzdata locales \
        build-essential pkg-config libssl-dev musl-tools \
        sqlite3 libsqlite3-dev tini \
 && rm -rf /var/lib/apt/lists/*

# cloudflared
ARG TARGETARCH=amd64
RUN curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${TARGETARCH}" \
 && chmod +x /usr/local/bin/cloudflared

# rustup must be able to install extra toolchains as a non-root user
RUN chmod -R a+w "${RUSTUP_HOME}" && rustup component add clippy rustfmt || true

RUN useradd -m -d /home/container container

# CARGO_HOME lives inside the server volume so the crate cache survives
# restarts and the user can clear it from the file manager.
ENV USER=container \
    HOME=/home/container \
    CARGO_HOME=/home/container/.cargo \
    CARGO_TERM_COLOR=always \
    DEBIAN_FRONTEND=noninteractive

USER container
WORKDIR /home/container

COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
CMD ["/bin/bash", "/entrypoint.sh"]
