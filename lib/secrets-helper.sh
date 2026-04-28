#!/usr/bin/env bash
# secrets-helper - Sourceable shell functions for tiered keychain access.
#
# Add to your ~/.zshrc or ~/.bashrc:
#   source /path/to/secrets-helper/lib/secrets-helper.sh
#
# Then use the bash functions directly:
#   get dev-secrets MY_TOKEN
#   add dev-secrets MY_TOKEN ghp_xxxxx
#   list dev-secrets
#
# These wrap the `secrets` CLI for convenience. They return the same exit
# codes and behavior — the only difference is namespace (no `secrets ` prefix).

if ! command -v secrets >/dev/null 2>&1; then
    echo "secrets-helper: 'secrets' CLI not found in PATH" >&2
    echo "  Add the bin/ directory of secrets-helper to your PATH first." >&2
    return 1 2>/dev/null || exit 1
fi

get()    { secrets get "$@"; }
add()    { secrets add "$@"; }
del()    { secrets del "$@"; }
list()   { secrets list "$@"; }
tiers()  { secrets tiers; }
lock()   { secrets lock "$@"; }
unlock() { secrets unlock "$@"; }
