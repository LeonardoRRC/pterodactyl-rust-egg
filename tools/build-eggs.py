#!/usr/bin/env python3
import json, pathlib, datetime

BASE = pathlib.Path(__file__).resolve().parent.parent
S = BASE / "runtime"

tpl = (BASE / "tools" / "install-embedded.sh.tpl").read_text()
for marker, fname in [
    ("@@ENTRYPOINT@@", "entrypoint.sh"),
    ("@@COMMON@@", "lib/common.sh"),
    ("@@GIT@@", "lib/git.sh"),
    ("@@RUST@@", "lib/rust.sh"),
    ("@@CLOUDFLARE@@", "lib/cloudflare.sh"),
]:
    tpl = tpl.replace(marker, (S / fname).read_text().rstrip("\n"))

assert "@@" not in tpl, "unsubstituted placeholders left"


OUT = BASE / "eggs"


def exported_at(path):
    """Keep the previous timestamp so rebuilding is deterministic and CI can
    diff the generated eggs against the committed ones."""
    try:
        return json.loads(path.read_text())["exported_at"]
    except Exception:
        return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def var(name, desc, env, default, rules, editable=True, viewable=True):
    return {
        "name": name,
        "description": desc,
        "env_variable": env,
        "default_value": default,
        "user_viewable": viewable,
        "user_editable": editable,
        "rules": rules,
        "field_type": "text",
    }


variables = [
    # ---------------- Source code ----------------
    var("Git repository",
        "HTTPS URL of the Rust project repository. Leave empty if you will upload the code manually through the file manager.",
        "GIT_REPO", "", "nullable|string|max:255"),
    var("Branch",
        "Branch or tag to deploy. Defaults to main.",
        "GIT_BRANCH", "main", "nullable|string|max:64"),
    var("Git username",
        "Username for private repositories. Leave empty for public repos.",
        "GIT_USER", "", "nullable|string|max:64"),
    var("Git token",
        "Personal Access Token for private repositories. It is only used during the fetch and is never stored in .git/config.",
        "GIT_TOKEN", "", "nullable|string|max:255", editable=True, viewable=False),
    var("Update on boot",
        "1 = run git fetch + reset to the branch on every boot. 0 = use the local code as-is.",
        "AUTO_UPDATE", "1", "required|boolean"),

    # ---------------- Toolchain ----------------
    var("Install rustup during installation",
        "1 = install rustup inside the server volume at install time (useful when the image has no Rust). 0 = use the Rust from the Docker image.",
        "INSTALL_RUSTUP", "0", "required|boolean"),
    var("Rust toolchain",
        "stable, beta, nightly or an exact version (1.85.0). Use 'default' to leave the image toolchain untouched.",
        "RUST_TOOLCHAIN", "stable", "nullable|string|max:32"),
    var("Build target",
        "Optional target triple, e.g. x86_64-unknown-linux-musl. Empty = native target.",
        "RUST_TARGET", "", "nullable|string|max:64"),

    # ---------------- Build ----------------
    var("Build on boot",
        "1 = run cargo build on every boot. 0 = start the already compiled binary directly.",
        "BUILD_ON_BOOT", "1", "required|boolean"),
    var("Build profile",
        "release (optimized) or debug (builds faster, slower binary).",
        "BUILD_PROFILE", "release", "required|in:release,debug"),
    var("Cargo binary (--bin)",
        "Name of the binary to build when the project or workspace has several. Empty = default.",
        "CARGO_BIN", "", "nullable|string|max:64"),
    var("Features",
        "Comma-separated feature list passed to --features.",
        "CARGO_FEATURES", "", "nullable|string|max:255"),
    var("Extra cargo flags",
        "Additional arguments for cargo build, e.g. --locked --no-default-features.",
        "CARGO_FLAGS", "", "nullable|string|max:255"),

    # ---------------- Runtime ----------------
    var("Binary name",
        "Executable name inside target/<profile>/. Empty = auto-detected from Cargo.toml.",
        "BINARY_NAME", "", "nullable|string|max:64"),
    var("Application arguments",
        "Arguments passed to your binary. Environment variables are supported: --port ${SERVER_PORT} --bind ${BIND_ADDR}",
        "APP_ARGS", "", "nullable|string|max:512"),
    var("Custom startup command",
        "Fully overrides the final command. It runs through bash, so it supports variables (${SERVER_PORT}, ${SERVER_MEMORY}, ${PXSVC_BIN}) and pipes. Example: ${PXSVC_BIN} serve --port ${SERVER_PORT}",
        "CUSTOM_STARTUP", "", "nullable|string|max:512"),
    var("Extra environment variables",
        "KEY=value pairs separated by ';'. Example: DATABASE_URL=postgres://...;APP_ENV=production",
        "ENV_VARS", "", "nullable|string|max:1024"),
    var("RUST_LOG",
        "Log level for the log/tracing crates: error, warn, info, debug, trace, or per-module filters.",
        "RUST_LOG", "info", "nullable|string|max:255"),
    var("RUST_BACKTRACE",
        "0 = no backtrace, 1 = backtrace, full = full backtrace on panics.",
        "RUST_BACKTRACE", "0", "required|in:0,1,full"),

    # ---------------- Cloudflare ----------------
    var("Enable Cloudflare Tunnel",
        "1 = publish the service on the internet through Cloudflare Tunnel (no open ports, node IP stays hidden).",
        "CF_ENABLED", "0", "required|boolean"),
    var("Tunnel mode",
        "off - quick (temporary *.trycloudflare.com URL, no account needed) - token (paste the dashboard token) - named (browser login, creates the tunnel and DNS record and generates your token).",
        "CF_MODE", "off", "required|in:off,quick,token,named"),
    var("Tunnel token",
        "Token from Zero Trust -> Networks -> Tunnels. Only used when CF_MODE=token.",
        "CF_TOKEN", "", "nullable|string|max:1024", editable=True, viewable=False),
    var("Tunnel name",
        "Tunnel name used by CF_MODE=named. Empty = generated from the server UUID.",
        "CF_TUNNEL_NAME", "", "nullable|string|max:64"),
    var("Public hostname",
        "Subdomain that will point to the service, e.g. api.mydomain.com. In named mode the DNS record is created automatically.",
        "CF_HOSTNAME", "", "nullable|string|max:255"),
    var("Local service",
        "Internal tunnel destination. Empty = http://127.0.0.1:${SERVER_PORT}. Use tcp://127.0.0.1:PORT for non-HTTP services.",
        "CF_SERVICE_URL", "", "nullable|string|max:255"),
    var("Tunnel protocol",
        "auto, http2 or quic. Use http2 if the node blocks UDP/7844.",
        "CF_PROTOCOL", "auto", "required|in:auto,http2,quic"),
]

RUNTIME_URL_DEFAULT = "https://raw.githubusercontent.com/LeonardoRRC/pterodactyl-rust-service/main/runtime"

remote_var = var(
    "Runtime source URL",
    "Base URL the install script downloads the pxsvc runtime from. Point it at a tag instead of main to pin a version. Admin only.",
    "RUNTIME_URL", RUNTIME_URL_DEFAULT, "required|string|max:255",
    editable=False, viewable=False,
)

egg = {
    "_comment": "Rust Service Egg - pxsvc runtime (git + cargo + Cloudflare Tunnel). Built for Pterodactyl / Pelican.",
    "meta": {"version": "PTDL_v2", "update_url": None},
    "exported_at": exported_at(OUT / "egg-rust-service-embedded.json"),
    "name": "Rust Service (Cargo + Cloudflare Tunnel)",
    "author": "admin@example.com",
    "description": (
        "Host and build services written in Rust. Syncs the source from Git, manages the toolchain with "
        "rustup, builds with cargo (configurable profile, features, target and flags), allows a fully custom "
        "startup command, and ships a Cloudflare Tunnel reverse proxy with three modes: temporary URL, "
        "dashboard token, or interactive login that creates the tunnel, the DNS record and the access token."
    ),
    "features": None,
    "docker_images": {
        "Rust - custom image (recommended)": "ghcr.io/LeonardoRRC/pterodactyl-rust-service:latest",
        "Rust latest (yolks)": "ghcr.io/parkervcp/yolks:rust_latest",
        "Rust 1.85 (yolks)": "ghcr.io/parkervcp/yolks:rust_1.85",
        "Debian (run pre-compiled binaries only)": "ghcr.io/parkervcp/yolks:debian",
    },
    "file_denylist": [],
    "startup": "bash .pxsvc/entrypoint.sh",
    "config": {
        "files": "{}",
        "startup": '{"done": ["[pxsvc] service is running"], "strip_ansi": false}',
        "logs": "{}",
        "stop": "^C",
    },
    "scripts": {
        "installation": {
            "script": tpl,
            "container": "ghcr.io/parkervcp/installers:debian",
            "entrypoint": "bash",
        }
    },
    "variables": variables,
}

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "egg-rust-service-embedded.json").write_text(json.dumps(egg, indent=4, ensure_ascii=False) + "\n")

# ---- remote variant: the install script downloads the runtime from GitHub ----
remote_tpl = (BASE / "tools" / "install-remote.sh.tpl").read_text()
assert "@@" not in remote_tpl

remote = json.loads(json.dumps(egg))
remote["_comment"] = (
    "Rust Service Egg (remote runtime) - the install script downloads runtime/ from GitHub. "
    "Update RUNTIME_URL to point at your repository."
)
remote["exported_at"] = exported_at(OUT / "egg-rust-service-remote.json")
remote["name"] = "Rust Service (Cargo + Cloudflare Tunnel) [remote runtime]"
remote["description"] = egg["description"] + " The runtime scripts are fetched from GitHub at install time."
remote["scripts"]["installation"]["script"] = remote_tpl
remote["variables"] = [remote_var] + variables
(OUT / "egg-rust-service-remote.json").write_text(json.dumps(remote, indent=4, ensure_ascii=False) + "\n")

print("variables:", len(variables), "| remote:", len(remote["variables"]))
print("embedded install script:", len(tpl), "bytes | remote:", len(remote_tpl), "bytes")
