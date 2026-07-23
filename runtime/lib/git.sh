#!/bin/bash
# ============================================================
#  pxsvc :: git.sh  ·  source code synchronization
# ============================================================

pxsvc_git_auth_url() {
    local url="$1"
    if [ -n "${GIT_USER}" ] && [ -n "${GIT_TOKEN}" ]; then
        echo "${url}" | sed -E "s#^(https?://)#\1${GIT_USER}:${GIT_TOKEN}@#"
    elif [ -n "${GIT_TOKEN}" ]; then
        echo "${url}" | sed -E "s#^(https?://)#\1oauth2:${GIT_TOKEN}@#"
    else
        echo "${url}"
    fi
}

pxsvc_git_sync() {
    if [ -z "${GIT_REPO}" ]; then
        pxsvc_log "GIT_REPO is empty: using the code already present in /home/container"
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        pxsvc_warn "git is not available in this image; skipping synchronization"
        return 0
    fi

    pxsvc_step "Synchronizing source code"
    local branch="${GIT_BRANCH:-main}"
    local auth_url
    auth_url="$(pxsvc_git_auth_url "${GIT_REPO}")"

    git config --global --add safe.directory /home/container >/dev/null 2>&1

    if [ ! -d .git ]; then
        pxsvc_log "Initializing repository from ${GIT_REPO} (branch ${branch})"
        git init -q .
        git remote add origin "${auth_url}" 2>/dev/null || git remote set-url origin "${auth_url}"
        if ! git fetch --depth 1 origin "${branch}"; then
            git remote set-url origin "${GIT_REPO}"
            pxsvc_die "Could not clone the repository (wrong URL, branch or token?)"
        fi
        git checkout -f -B "${branch}" FETCH_HEAD >/dev/null 2>&1
    elif pxsvc_bool "${AUTO_UPDATE}"; then
        pxsvc_log "Updating to origin/${branch}"
        git remote set-url origin "${auth_url}"
        if git fetch --depth 1 origin "${branch}"; then
            git checkout -f -B "${branch}" FETCH_HEAD >/dev/null 2>&1
        else
            pxsvc_warn "Update failed; continuing with the local copy"
        fi
    else
        pxsvc_log "AUTO_UPDATE disabled: using the local copy"
    fi

    # Never leave the token stored in .git/config
    git remote set-url origin "${GIT_REPO}" 2>/dev/null

    if [ -f .gitmodules ]; then
        pxsvc_log "Updating submodules"
        git submodule update --init --recursive --depth 1 >/dev/null 2>&1 || pxsvc_warn "Submodules: partial failure"
    fi

    pxsvc_ok "HEAD → $(git log -1 --pretty='%h · %s' 2>/dev/null || echo 'unknown')"
}
