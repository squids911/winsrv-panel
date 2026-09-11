#!/usr/bin/env bash
# setup_git.sh — восстановить доступ к GitHub после сброса среды (sandbox).
#
# Среда теряет между сессиями: установленные пакеты (gh), .git/config
# (remote origin), частично git-идентичность. Этот скрипт всё это
# восстанавливает, опираясь на то, что СОХРАНЯЕТСЯ:
#   * файлы проекта в /home/user (в т.ч. сам репозиторий);
#   * ~/.config/gh/hosts.yml (токен GitHub CLI).
#
# Запуск:  bash setup_git.sh
#          (или: ./setup_git.sh)

set -u
REPO_URL="https://github.com/squids911/winsrv-panel.git"
REPO_USER="squids911"
REPO_EMAIL="squids911@users.noreply.github.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

log()  { printf "==> %s\n" "$*"; }
info() { printf "    %s\n" "$*"; }
err()  { printf "ERROR: %s\n" "$*" >&2; }

cd "$PROJECT_DIR" || { err "Cannot cd to $PROJECT_DIR"; exit 1; }

# 1) GitHub CLI (gh)
log "Check gh CLI..."
if ! command -v gh >/dev/null 2>&1; then
    info "gh not found. Installing via apt..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq gh || { err "Failed to install gh (please install it manually)."; }
    else
        err "gh missing and apt-get unavailable. Install GitHub CLI manually."
        exit 1
    fi
fi
info "gh version: $(gh --version 2>/dev/null | head -1)"

# 2) GitHub CLI auth
log "Check gh authentication..."
if ! gh auth status >/dev/null 2>&1; then
    info "Not authenticated via gh."
    if [ -n "${GH_TOKEN:-}" ]; then
        info "GH_TOKEN found in env, using it."
        printf '%s' "$GH_TOKEN" | gh auth login --hostname github.com --git-protocol https --with-token || true
    else
        info "No GH_TOKEN env. Provide access:"
        info "  Option A: run:  gh auth login --with-token  (pipe a Personal Access Token)"
        info "         or:  gh auth login  (browser/device flow)"
        info "  Option B: set GH_TOKEN env var and rerun this script."
        # Don't hard-fail: git auth may still work if credentials exist further below.
    fi
fi
if gh auth status >/dev/null 2>&1; then
    gh auth status 2>&1 | sed 's/^/    /'
    info "Authenticated as: $(gh api user --jq .login 2>/dev/null)"
    # Make git use gh as a credential helper.
    log "Setup git credential helper (gh)..."
    gh auth setup-git || true
else
    err "gh authentication not available. git push may prompt for credentials."
fi

# 3) Git identity + remote (these are reset together with .git/config)
log "Set git identity..."
git config user.name  "$REPO_USER"
git config user.email "$REPO_EMAIL"

log "Set remote 'origin'..."
git remote remove origin 2>/dev/null
git remote add origin "$REPO_URL"
info "origin -> $(git remote get-url origin)"

# 4) Ensure we are on 'main' and sync
log "Ensure branch 'main' and fetch..."
git checkout -B main 2>/dev/null || true
git fetch origin main 2>&1 | sed 's/^/    /' || true

# 5) Show net status
log "Status:"
git status -sb | sed 's/^/    /' || true
_oh="$(git log --oneline -1 origin/main 2>/dev/null || true)"
[ -n "$_oh" ] && info "origin/HEAD: $_oh"

log "Git/GitHub setup complete."
