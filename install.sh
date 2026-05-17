#!/usr/bin/env bash
# Non-interactive secrets-helper installer.
# Installs the CLI entrypoint and verifies prerequisites; does not create keychains
# or write ~/.config/secrets-helper/config.sh. Run ./setup.sh for first-time setup.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")"
readonly BIN_DIR="${SECRETS_HELPER_BIN_DIR:-$HOME/.local/bin}"
readonly TARGET="$BIN_DIR/secrets"
readonly SOURCE="$SCRIPT_DIR/bin/secrets"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/secrets-helper"
readonly CONFIG_FILE="$CONFIG_DIR/config.sh"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "secrets-helper currently requires macOS Keychain (Darwin)." >&2
    exit 1
  fi
}

require_security_cli() {
  if ! command -v security >/dev/null 2>&1; then
    echo "macOS security(1) command not found." >&2
    exit 1
  fi
}

install_cli() {
  if [[ ! -x "$SOURCE" ]]; then
    echo "Missing executable CLI: $SOURCE" >&2
    exit 1
  fi

  mkdir -p "$BIN_DIR"
  ln -sf "$SOURCE" "$TARGET"
  log "Linked secrets CLI: $TARGET -> $SOURCE"
}

print_next_steps() {
  echo ""
  echo "secrets-helper $VERSION installed."
  echo ""
  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not on PATH. Add this to your shell rc:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo ""
  fi

  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "First-time setup still needed:"
    echo "  $SCRIPT_DIR/setup.sh"
  else
    echo "Existing config found: $CONFIG_FILE"
    echo "Try: secrets tiers"
  fi
}

main() {
  require_macos
  require_security_cli
  install_cli
  print_next_steps
}

main "$@"
