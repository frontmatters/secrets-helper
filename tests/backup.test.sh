#!/usr/bin/env bash
# backup.test.sh — the backup password reaches python on stdin and never its
# environment (review fix 7); restore adds the tiers to the keychain search
# list and keeps every other entry (review fix 6).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ [[ "$2" == "$3" ]] && ok "$1" || nope "$1" "expected: $3 / actual: $2"; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home/Library/Keychains"
KC="$WORK/home/Library/Keychains"
printf 'TIER_NAMES=("dev-secrets" "prod-secrets")\nTIER_POLICIES=("1" "2")\nTIER_DESCS=("d" "p")\n' > "$WORK/config.sh"; chmod 600 "$WORK/config.sh"
: > "$KC/dev-secrets.keychain-db"; : > "$KC/prod-secrets.keychain-db"; : > "$KC/login.keychain-db"; : > "$KC/other-app.keychain-db"
# python3 stand-in: records whether the password is in its environment and what came on stdin
cat > "$WORK/bin/python3" <<EOF2
#!/usr/bin/env bash
env | grep -q '^SECRETS_BACKUP_PASSWORD=' && echo yes > "$WORK/env-seen" || echo no > "$WORK/env-seen"
cat > "$WORK/stdin-seen"
printf '%s\n' "\$*" > "$WORK/python-args"
exit 0
EOF2
# security stand-in: a search list kept in a file
printf '%s\n' "$KC/login.keychain-db" "$KC/other-app.keychain-db" > "$WORK/searchlist"
cat > "$WORK/bin/security" <<EOF2
#!/usr/bin/env bash
if [[ "\$1" == list-keychains ]]; then
  shift; [[ "\${1:-}" == -d ]] && shift 2
  if [[ "\${1:-}" == -s ]]; then shift; printf '%s\n' "\$@" > "$WORK/searchlist"; exit 0; fi
  sed 's/^/    "/; s/\$/"/' "$WORK/searchlist"; exit 0
fi
exit 0
EOF2
chmod +x "$WORK/bin/"*
run() { ( export HOME="$WORK/home" SECRETS_HELPER_CONFIG="$WORK/config.sh" SECRETS_KEYCHAIN_DIR="$KC" PATH="$WORK/bin:$PATH"
          "${SECRETS_BIN:-./bin/secrets}" "$@" </dev/null 2>&1 ); }

echo "== backup and restore =="
SECRETS_BACKUP_PASSWORD="bk-pw-123" run backup --out "$WORK/b.secbak" dev-secrets >/dev/null
check "the password is not in python's environment" "$(cat "$WORK/env-seen")" "no"
check "python gets it on stdin"                      "$(cat "$WORK/stdin-seen")" "bk-pw-123"
[[ "$(cat "$WORK/python-args")" != *bk-pw-123* ]] && ok "and not as an argument" || nope "password in python's arguments"

: > "$WORK/b.secbak"
SECRETS_BACKUP_PASSWORD="bk-pw-123" run restore "$WORK/b.secbak" >/dev/null
check "restore keeps every earlier search-list entry, in order, and adds the tiers" \
  "$(tr '\n' ' ' < "$WORK/searchlist")" "$KC/login.keychain-db $KC/other-app.keychain-db $KC/dev-secrets.keychain-db $KC/prod-secrets.keychain-db "
SECRETS_BACKUP_PASSWORD="bk-pw-123" run restore "$WORK/b.secbak" >/dev/null
check "a second restore adds nothing twice" "$(grep -c . "$WORK/searchlist")" "4"
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
