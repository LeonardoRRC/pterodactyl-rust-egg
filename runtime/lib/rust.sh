#!/bin/bash
# ============================================================
#  pxsvc :: rust.sh  ·  toolchain and compilation
# ============================================================

pxsvc_ensure_toolchain() {
    pxsvc_step "Preparing the Rust toolchain"

    if ! command -v cargo >/dev/null 2>&1; then
        pxsvc_warn "cargo is not in the image; installing rustup into /home/container (this may take several minutes)"
        if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
             | sh -s -- -y --no-modify-path --profile minimal \
                       --default-toolchain "${RUST_TOOLCHAIN:-stable}"; then
            pxsvc_die "Could not install rustup. Use a Docker image that ships with Rust."
        fi
        export PATH="${CARGO_HOME}/bin:${PATH}"
    fi

    if command -v rustup >/dev/null 2>&1 \
       && [ -n "${RUST_TOOLCHAIN}" ] && [ "${RUST_TOOLCHAIN}" != "default" ]; then
        if ! rustup toolchain list 2>/dev/null | grep -q "^${RUST_TOOLCHAIN}"; then
            pxsvc_log "Installing toolchain ${RUST_TOOLCHAIN}"
            rustup toolchain install "${RUST_TOOLCHAIN}" --profile minimal \
                || pxsvc_warn "Could not install ${RUST_TOOLCHAIN}; falling back to the default toolchain"
        fi
        rustup default "${RUST_TOOLCHAIN}" >/dev/null 2>&1
    fi

    if [ -n "${RUST_TARGET}" ] && command -v rustup >/dev/null 2>&1; then
        pxsvc_log "Adding target ${RUST_TARGET}"
        rustup target add "${RUST_TARGET}" >/dev/null 2>&1 \
            || pxsvc_warn "Could not add target ${RUST_TARGET}"
    fi

    command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
        || pxsvc_warn "No linker (cc/gcc) in this image: the build will fail. Use an image with build-essential or set BUILD_ON_BOOT=0."

    [ -f rust-toolchain.toml ] || [ -f rust-toolchain ] \
        && pxsvc_log "The repository pins its own toolchain (rust-toolchain); it takes precedence"

    pxsvc_ok "$(cargo --version 2>/dev/null) · $(rustc --version 2>/dev/null)"
}

pxsvc_build() {
    if ! pxsvc_bool "${BUILD_ON_BOOT}"; then
        pxsvc_log "BUILD_ON_BOOT disabled: skipping compilation"
        return 0
    fi
    if [ ! -f Cargo.toml ]; then
        pxsvc_warn "No Cargo.toml in /home/container; skipping compilation"
        return 0
    fi

    pxsvc_step "Building project (profile: ${BUILD_PROFILE:-release})"

    local -a args=(build)
    [ "${BUILD_PROFILE}" != "debug" ] && args+=(--release)
    [ -n "${CARGO_BIN}" ]      && args+=(--bin "${CARGO_BIN}")
    [ -n "${CARGO_FEATURES}" ] && args+=(--features "${CARGO_FEATURES}")
    [ -n "${RUST_TARGET}" ]    && args+=(--target "${RUST_TARGET}")
    # shellcheck disable=SC2206
    [ -n "${CARGO_FLAGS}" ]    && args+=(${CARGO_FLAGS})

    local start=${SECONDS}
    echo -e "${C_DIM}container@pterodactyl:~$ cargo ${args[*]}${C_RESET}"
    cargo "${args[@]}"
    local rc=$?

    if [ ${rc} -ne 0 ]; then
        pxsvc_err "Build failed (exit code ${rc})"
        pxsvc_err "Check the cargo output above. The server will stop."
        exit ${rc}
    fi
    pxsvc_ok "Build finished in $((SECONDS - start))s"
}
