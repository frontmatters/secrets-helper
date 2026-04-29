#!/usr/bin/env bash
# keybuddy - Sourceable shell functions for tiered keychain access.
#
# Add to your ~/.zshrc or ~/.bashrc:
#   source /path/to/keybuddy/lib/keybuddy.sh
#
# Then use the bash functions directly:
#   get dev-secrets MY_TOKEN
#   add dev-secrets MY_TOKEN ghp_xxxxx
#   list dev-secrets
#
# These wrap the `secrets` CLI for convenience. They return the same exit
# codes and behavior — the only difference is namespace (no `secrets ` prefix).

# Load user preferences (banner, etc.). Created by setup.sh.
_kb_prefs="${XDG_CONFIG_HOME:-$HOME/.config}/keybuddy/preferences.sh"
[[ -f "$_kb_prefs" ]] && source "$_kb_prefs"
unset _kb_prefs

if ! command -v secrets >/dev/null 2>&1; then
    echo "keybuddy: 'secrets' CLI not found in PATH" >&2
    echo "  Add the bin/ directory of keybuddy to your PATH first." >&2
    return 1 2>/dev/null || exit 1
fi

get()    { secrets get "$@"; }
add()    { secrets add "$@"; }
del()    { secrets del "$@"; }
list()   { secrets list "$@"; }
tiers()  { secrets tiers; }
lock()   { secrets lock "$@"; }
unlock() { secrets unlock "$@"; }

# Load confirmation banner. Suppressed when KEYBUDDY_QUIET=1 (env var or
# preferences.sh, set during `setup.sh` or by exporting in your shell rc).
if [[ -z "${KEYBUDDY_QUIET:-}" ]]; then
    _kb_v=$(secrets --version 2>/dev/null | awk '{print $2}')
    echo "keybuddy ${_kb_v:-?} loaded — try \`tiers\` to see your configured tiers"
    unset _kb_v
fi
