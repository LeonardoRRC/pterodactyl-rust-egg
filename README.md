# Rust Service Egg · Pterodactyl

Egg for **hosting and building services written in Rust**, with Git-based deployment,
`cargo` builds, a fully configurable startup command and a **Cloudflare Tunnel reverse
proxy** (no open ports, node IP stays hidden).

```
eggs/
  egg-rust-service-embedded.json   <- runtime embedded in the install script (no external deps)
  egg-rust-service-remote.json     <- install script downloads runtime/ from this repo
runtime/                           <- the pxsvc runtime (entrypoint + libs)
docker/                            <- Docker image published to GHCR
tools/build-eggs.py                <- regenerates both eggs from runtime/
.github/workflows/                 <- image publishing + validation
```

---

## 0. Publishing this repository

```bash
git init -b main
git add .
git commit -m "Rust service egg for Pterodactyl"
git remote add origin https://github.com/YOUR_USER/pterodactyl-rust-service.git
git push -u origin main
```

Then set your own values. Three of them belong in `tools/egg.config.json`, **not** in the
eggs themselves — `tools/build-eggs.py` regenerates `eggs/*.json`, so anything you type
directly into those files gets reverted on the next build and CI fails:

```json
{
    "author": "you@example.com",
    "docker_images": {
        "Rust - custom image (recommended)": "ghcr.io/YOUR_USER/pterodactyl-rust-service:latest",
        "Rust latest (yolks)": "ghcr.io/parkervcp/yolks:rust_latest",
        "Debian (run pre-compiled binaries only)": "ghcr.io/parkervcp/yolks:debian"
    },
    "runtime_url": "https://raw.githubusercontent.com/YOUR_USER/pterodactyl-rust-service/main/runtime"
}
```

Then `python3 tools/build-eggs.py` and commit. Resolution order for these three values:

1. environment variables (`EGG_AUTHOR`, `RUNTIME_URL`) — useful in CI,
2. `tools/egg.config.json`,
3. whatever is already committed in `eggs/*.json` — so an existing manual edit survives,
4. the built-in placeholder.

`LICENSE` still needs its copyright holder replaced by hand.

`git push` triggers **Build and publish image**, which builds `docker/Dockerfile` for
amd64 and arm64 and pushes it to `ghcr.io/YOUR_USER/pterodactyl-rust-service:latest`.
No secrets to configure: it uses the automatic `GITHUB_TOKEN`.

> **The first push publishes a private package.** Wings cannot pull it until you go to
> your profile → **Packages** → `pterodactyl-rust-service` → **Package settings** →
> **Change visibility → Public**. Do this once; a private image fails with
> `manifest unknown` or `unauthorized` on the node.

Tag a release to pin a version: `git tag v1.0.0 && git push --tags` produces the
`:v1.0.0` tag alongside `:latest`.

The **Validate eggs and runtime** workflow checks the shell syntax of every script,
verifies the `done` marker still exists in the runtime, and fails if `eggs/` is out of
date with respect to `runtime/`.

### After editing anything in `runtime/`

```bash
python3 tools/build-eggs.py   # re-embeds the scripts into eggs/*.json
git commit -am "runtime: ..." && git push
```

---

## 1. Which egg to import

| | `embedded` | `remote` |
|---|---|---|
| Runtime source | inside the install script | downloaded from `RUNTIME_URL` |
| Works without internet access to GitHub | yes | no |
| Updating the runtime | re-import the egg into the panel | just push to the repo, then reinstall the server |
| Extra variable | — | `RUNTIME_URL` (admin only, hidden from clients) |

The `remote` variant is the practical one if you host for other people: fix a bug in
`runtime/lib/cloudflare.sh`, push, and every new install picks it up. Point `RUNTIME_URL`
at a tag (`.../v1.0.0/runtime`) instead of `main` if you would rather pin versions and
roll them out deliberately.

`RUNTIME_URL` is marked non-editable and non-viewable: clients cannot repoint it at
arbitrary scripts, since the install script runs them.

---

## 2. Installation

1. **Admin → Nests → Import Egg** → upload one of the files in `eggs/`.
2. Check `docker_images`: use your published image, or `ghcr.io/parkervcp/yolks:rust_latest`
   (verify the tags that currently exist in the yolks repo).
3. Create a server with this egg. The install script:
   - installs the runtime into `/home/container/.pxsvc/`,
   - downloads `cloudflared`,
   - clones your repository (or creates an example project if `GIT_REPO` is empty).

> **Important:** building requires a linker (`cc`) and the OpenSSL headers.
> If you use an image without `build-essential`, set `BUILD_ON_BOOT=0` and upload the
> pre-compiled binary, or use the image in `docker/Dockerfile`.

### Recommended resources
`cargo build --release` is RAM and disk intensive. For medium projects:
**≥ 2 GB RAM** and **≥ 5 GB disk** (the `target/` directory grows fast).
If the build dies without a message, it is almost always the OOM killer: raise the RAM
limit or build in `debug`.

---

## 3. Boot flow

```
env → git sync → toolchain (rustup) → cargo build → Cloudflare Tunnel → exec the service
```

The panel startup command is always:

```
bash .pxsvc/entrypoint.sh
```

Everything else is driven by variables, so the end user never has to touch the startup
line to change the port, features, arguments or profile.

---

## 4. Variables

### Source code
| Variable | Purpose |
|---|---|
| `GIT_REPO` | HTTPS repository URL. Empty = use manually uploaded code. |
| `GIT_BRANCH` | Branch or tag (`main` by default). |
| `GIT_USER` / `GIT_TOKEN` | Credentials for private repos. The token is never stored in `.git/config`. |
| `AUTO_UPDATE` | `1` = `fetch` + `reset` to the branch on every boot. |

### Toolchain and build
| Variable | Purpose |
|---|---|
| `INSTALL_RUSTUP` | Installs rustup inside the server volume during installation. |
| `RUST_TOOLCHAIN` | `stable`, `beta`, `nightly`, `1.85.0`, or `default` to leave the image toolchain alone. |
| `RUST_TARGET` | Optional triple, e.g. `x86_64-unknown-linux-musl`. |
| `BUILD_ON_BOOT` | `0` to start without rebuilding (instant boots). |
| `BUILD_PROFILE` | `release` or `debug`. |
| `CARGO_BIN` | `--bin` when the workspace has several binaries. |
| `CARGO_FEATURES` | Passed to `--features`. |
| `CARGO_FLAGS` | Extras: `--locked`, `--no-default-features`, `-p my-crate`… |

### Runtime
| Variable | Purpose |
|---|---|
| `BINARY_NAME` | Executable inside `target/<profile>/`. Empty = auto-detected from `Cargo.toml`. |
| `APP_ARGS` | Binary arguments. Supports `${SERVER_PORT}`, `${BIND_ADDR}`, etc. |
| `CUSTOM_STARTUP` | Fully replaces the final command. |
| `ENV_VARS` | `KEY=value` pairs separated by `;`. |
| `RUST_LOG` / `RUST_BACKTRACE` | Logging and backtraces. |

### Cloudflare
| Variable | Purpose |
|---|---|
| `CF_ENABLED` | Enables the tunnel. |
| `CF_MODE` | `off`, `quick`, `token`, `named`. |
| `CF_TOKEN` | Dashboard token (`token` mode). Hidden from the user. |
| `CF_TUNNEL_NAME` | Tunnel name (`named` mode). |
| `CF_HOSTNAME` | Public subdomain, e.g. `api.mydomain.com`. |
| `CF_SERVICE_URL` | Internal destination. Empty = `http://127.0.0.1:${SERVER_PORT}`. |
| `CF_PROTOCOL` | `auto`, `http2` or `quic`. Use `http2` if the node filters UDP/7844. |

> Pterodactyl only renders text fields, but the real "input type" comes from the
> validation `rules`: `boolean` accepts 0/1, `in:release,debug` restricts the allowed
> values, and `nullable|string|max:N` controls length. The panel rejects anything outside
> that list, so it behaves like a select. On **Pelican** you can turn those same rules
> into native selects without touching the scripts.

---

## 5. Customizing the startup command

Variables exported before your service is executed:

| Variable | Value |
|---|---|
| `${SERVER_PORT}` | primary allocation port |
| `${BIND_ADDR}` | `0.0.0.0:${SERVER_PORT}` |
| `${SERVER_MEMORY}` | allocated RAM in MB |
| `${PXSVC_BIN}` | path to the detected binary |
| `${INTERNAL_IP}` | container internal IP |

**`CUSTOM_STARTUP` examples:**

```bash
# typical web server
${PXSVC_BIN} --bind ${BIND_ADDR} --workers 4

# configuration through the environment
DATABASE_URL=$DATABASE_URL ${PXSVC_BIN} serve --port ${SERVER_PORT}

# run through cargo instead of the binary
cargo run --release --bin api -- --port ${SERVER_PORT}

# migrations before starting
sqlx migrate run && ${PXSVC_BIN} --port ${SERVER_PORT}
```

If you would rather not use `CUSTOM_STARTUP`, just set `APP_ARGS`:
`--config config.toml --port ${SERVER_PORT}`.

---

## 6. Cloudflare reverse proxy

### `quick` mode — test in 10 seconds
`CF_ENABLED=1`, `CF_MODE=quick`. No account or domain needed: a
`https://xxxx.trycloudflare.com` URL is printed in the console on boot (and saved to
`.pxsvc/logs/tunnel-url.txt`). The URL changes on every restart → testing only.

### `named` mode — the user logs in and generates their token
`CF_ENABLED=1`, `CF_MODE=named`, `CF_HOSTNAME=api.mydomain.com`.

On the first boot the console prints a Cloudflare URL. The user opens it, logs in,
authorizes their domain, and startup continues on its own. The runtime then:

1. saves the session to `.cloudflared/cert.pem`,
2. creates the tunnel (or reuses an existing one),
3. creates the DNS record for the hostname,
4. writes `.cloudflared/config.yml` with the ingress rules,
5. **generates the tunnel token** into `.cloudflared/token.txt` (mode 600; only the first
   and last few characters are shown in the console so it does not leak into the logs).

That token can later be pasted into `CF_TOKEN` with `CF_MODE=token` so subsequent boots
need no login.

### `token` mode — production
Create the tunnel in **Zero Trust → Networks → Tunnels**, define the ingress rules in the
dashboard and paste the token into `CF_TOKEN`. This is the recommended mode for clients:
the token is revocable, the configuration lives in Cloudflare and boots are non-interactive.

### Non-HTTP services
`CF_SERVICE_URL=tcp://127.0.0.1:${SERVER_PORT}`. Clients connect with
`cloudflared access tcp --hostname my.host --url localhost:5432`.
For HTTPS with a self-signed certificate behind the tunnel, add `noTLSVerify` to the
dashboard ingress rules or edit `.cloudflared/config.yml`.

---

## 7. Recipes

**Workspace with multiple binaries**
```
CARGO_BIN=api
BINARY_NAME=api
CARGO_FLAGS=-p api --locked
```

**Pre-compiled binary (no toolchain)**
```
BUILD_ON_BOOT=0
RUST_TOOLCHAIN=default
BINARY_NAME=my-service      # upload it to target/release/
Image: yolks:debian
```

**Reproducible static build**
```
RUST_TARGET=x86_64-unknown-linux-musl
CARGO_FLAGS=--locked
```

---

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `linker cc not found` | The image has no `build-essential`. Use the image in `docker/`. |
| `failed to run custom build command for openssl-sys` | Missing `libssl-dev`/`pkg-config`, or use the openssl `vendored` feature. |
| Build stops with no error | OOM. Raise the RAM, use `BUILD_PROFILE=debug` or `CARGO_FLAGS=-j 2`. |
| Server stuck on "starting" | The `[pxsvc] service is running` marker is missing; check the `config.startup` block of the egg. |
| Tunnel does not connect | Try `CF_PROTOCOL=http2` (some nodes block UDP/7844). |
| Cloudflare `error 1033` | The tunnel is up but your service is not listening on `CF_SERVICE_URL` yet. |
| Disk full | Delete `target/` from the file manager; `cargo` will regenerate it. |

---

## 9. Security

- `GIT_TOKEN` and `CF_TOKEN` are marked **not viewable** by the client: they can be
  written but not read back from the panel.
- The repository token is only used during the `fetch`; the remote is rewritten without
  credentials afterwards.
- The tunnel token is written to disk with mode `600` and never printed in full.
- A Cloudflare Tunnel token grants control over that tunnel's routing: treat it like a
  password and revoke it from the dashboard if it leaks.
