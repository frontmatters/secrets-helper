#!/usr/bin/env bash
# config.test.sh — the config is only read when it is yours, not writable by
# others, and holds nothing but literal lists (security review, fix 8).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
contains(){ [[ "$2" == *"$3"* ]] && ok "$1" || nope "$1" "expected to contain: $3 / actual: $2"; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
run() { SECRETS_HELPER_CONFIG="$WORK/config.sh" SECRETS_KEYCHAIN_DIR="$WORK/kc" ./bin/secrets "$@" 2>&1; }
write() { printf '%s\n' "$@" > "$WORK/config.sh"; chmod 600 "$WORK/config.sh"; }

echo "== config =="
write '# a comment' 'TIER_NAMES=("dev-secrets" "prod-secrets")' "TIER_POLICIES=('1' 2)" 'TIER_DESCS=("Dev, with \"quotes\"" "Prod")' 'NEVER_PULL_TIERS=(quarantine)'
contains "a plain config is read"                "$(run tiers)" "dev-secrets"
write 'TIER_NAMES=("dev")' "TIER_POLICIES=(\"1\")" "TIER_DESCS=(\"\$(touch $WORK/pwned)\")"
out=$(run tiers)
contains "a command substitution is refused"     "$out" "will not run"
[[ ! -e "$WORK/pwned" ]] && ok "and never runs" || nope "the command ran"
write 'TIER_NAMES=("dev")' 'TIER_POLICIES=("1")' 'TIER_DESCS=("`id`")'
contains "backticks are refused"                 "$(run tiers)" "will not run"
write 'TIER_NAMES=("dev")' 'TIER_POLICIES=("1")' 'TIER_DESCS=("x")' 'PATH=/tmp'
contains "an unknown key is refused"             "$(run tiers)" "will not run"
write 'TIER_NAMES=("dev")' 'TIER_POLICIES=("1")' 'TIER_DESCS=("x")' 'echo hi'
contains "a command line is refused"             "$(run tiers)" "will not run"
write 'TIER_NAMES=("dev")' 'TIER_POLICIES=("1")' 'TIER_DESCS=("x")'; chmod 664 "$WORK/config.sh"
contains "a config others can change is refused" "$(run tiers)" "can be changed by others"
chmod 600 "$WORK/config.sh"
contains "--version works without reading it"   "$(SECRETS_HELPER_CONFIG="$WORK/none.sh" ./bin/secrets --version)" "secrets-helper"
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
