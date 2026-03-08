#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-dev.sh [--verify-only] [--no-apt]

Options:
  --verify-only  Run verification steps only (no install attempts)
  --no-apt       Skip apt installs; fail with actionable hints if packages are missing
  -h, --help     Show this help message
EOF
}

log_step() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

verify_only=false
no_apt=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-only)
      verify_only=true
      ;;
    --no-apt)
      no_apt=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

required_commands=(curl git gcc make unzip jq)
apt_packages=(curl git build-essential unzip jq ca-certificates)
missing_commands=()

find_missing_commands() {
  missing_commands=()
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_commands+=("$cmd")
    fi
  done
}

ensure_system_deps() {
  find_missing_commands
  if ((${#missing_commands[@]} == 0)); then
    log_step "System dependencies already installed"
    return
  fi

  if [[ "$verify_only" == true ]]; then
    fail "Missing required commands in --verify-only mode: ${missing_commands[*]}. Run ./scripts/bootstrap-dev.sh first."
  fi

  if [[ "$no_apt" == true ]]; then
    fail "Missing required commands: ${missing_commands[*]}. Install manually with: sudo apt-get update && sudo apt-get install -y ${apt_packages[*]}"
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    fail "apt-get is not available. Install these commands manually: ${missing_commands[*]}"
  fi

  log_step "Installing missing system packages via apt"
  sudo apt-get update
  sudo apt-get install -y "${apt_packages[@]}"

  find_missing_commands
  if ((${#missing_commands[@]} > 0)); then
    fail "Still missing required commands after apt install: ${missing_commands[*]}"
  fi
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.config/nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    fail "nvm not found at $NVM_DIR/nvm.sh. Install nvm from https://github.com/nvm-sh/nvm"
  fi
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh" --no-use
}

use_node_20() {
  if [[ "$verify_only" == true ]]; then
    log_step "Selecting Node 20 with nvm (--verify-only)"
    nvm use 20 >/dev/null || fail "Node 20 is not installed in nvm. Run ./scripts/bootstrap-dev.sh first."
  else
    log_step "Installing and selecting Node 20 with nvm"
    nvm install 20
    nvm use 20
    nvm alias default 20 >/dev/null
  fi

  log_step "Active runtime versions"
  node -v
  npm -v
}

install_js_dependencies() {
  if [[ "$verify_only" == true ]]; then
    log_step "Skipping dependency installation (--verify-only)"
    return
  fi

  if [[ -f package-lock.json ]]; then
    log_step "Installing JavaScript dependencies with npm ci"
    npm ci
  else
    log_step "Installing JavaScript dependencies with npm install (creating lockfile)"
    npm install
  fi
}

run_verification() {
  log_step "Running lint checks"
  npm test

  log_step "Building distributable"
  npm run build
}

print_next_step() {
  log_step "Bootstrap complete"
  printf 'Start the local demo with: npm start\n'
}

main() {
  ensure_system_deps
  load_nvm
  use_node_20
  install_js_dependencies
  run_verification
  print_next_step
}

main
