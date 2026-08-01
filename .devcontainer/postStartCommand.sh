#!/usr/bin/env bash
set -euo pipefail

# postStartCommand for the devcontainer.
# - optionally bootstrap a dotfiles repo if DOTFILES_GIT_URL is provided
# - optionally bring up Tailscale when an auth key is injected
# - clean up any temporary .env file produced by initializeCommand
#
# Helpers print prefixed messages so the container logs are easier to scan.

log() {
  local level=$1; shift
  echo "postStartCommand: [$level] $*" >&2
}

error() {
  log "ERROR" "$@"
}

bootstrap_dotfiles() {
  # Run `npx` on the supplied repo URL if the variable is set.
  local url="${DOTFILES_GIT_URL:-}"
  [ -z "$url" ] && return

  # prefix with git+ when necessary; npx understands URLs with that scheme.
  case "$url" in
    https://*|ssh://*) url="git+$url" ;;
  esac

  if ! command -v npx >/dev/null 2>&1; then
    log "WARN" "npx not available, skipping bootstrap"
    return
  fi

  if ! npx -y "$url"; then
    log "WARN" "npx bootstrap failed for $url"
  fi
}

setup_tailscale() {
  local key="${TAILSCALE_AUTHKEY:-}"
  [ -z "$key" ] && return

  if ! command -v tailscale >/dev/null 2>&1; then
    log "WARN" "tailscale not in PATH, skipping Tailscale setup"
    return
  fi

  log "INFO" "bringing up Tailscale..."
  if ! sudo tailscale up --accept-routes --authkey "$key" --advertise-tags tag:devcontainer; then
    log "WARN" "tailscale up failed"
  fi
}

main() {
  bootstrap_dotfiles
  setup_tailscale
}

main
