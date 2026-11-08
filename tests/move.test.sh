#!/usr/bin/env bash
# tests/move.test.sh — `secrets move`, promoting a secret from one tier to another.
#
# The interesting property is that a move must never be able to lose a secret:
# copy, verify the copy, and only then delete the original. Several tests here
# make the copy fail on purpose and assert the original survived.

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
nope() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ [[ "$2" == "$3" ]] && ok "$1" || nope "$1" "expected: $3
     actual:   $2"; }
contains(){ [[ "$2" == *"$3"* ]] && ok "$1" || nope "$1" "expected to contain: $3
     actual: $2"; }
lacks(){ [[ "$2" != *"$3"* ]] && ok "$1" || nope "$1" "must NOT contain: $3"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/config.sh" <<'EOF'
TIER_NAMES=("dev-secrets" "prod-secrets" "quarantine")
TIER_POLICIES=("1" "2" "2")
TIER_DESCS=("Dev tokens" "Infra" "Leaked, pending revocation")
EOF

# A `security` stand-in backed by one file per tier, so a move is observable.
cat > "$WORK/security" <<'EOF'
#!/usr/bin/env bash
DIR="${FAKE_KC_DIR:?}"
# `security -i`: commands on stdin, one per line, split as the real one does
# (shlex); each runs as its own call. Argument lists are recorded (not the
# inner calls), so a test can prove a value never reached one.
[[ -z "${FAKE_INNER:-}" ]] && printf '%s\n' "$*" >> "${FAKE_ARGV_LOG:-/dev/null}"
if [[ "${1:-}" == -i ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    args=()
    while IFS= read -r -d '' a; do args+=("$a"); done < <(printf '%s' "$line" | python3 -c 'import shlex,sys; sys.stdout.write("".join(a + "\0" for a in shlex.split(sys.stdin.read())))')
    [[ ${#args[@]} -gt 0 ]] && { FAKE_INNER=1 "$0" "${args[@]}" || exit $?; }
  done
  exit 0
fi
sub="$1"; shift
name=""; value=""; kc=""; want_value=0; prev=""
for a in "$@"; do
  case "$prev" in -s) name="$a" ;; -w) [[ "$sub" == add-generic-password ]] && value="$a" ;; esac
  [[ "$a" == -w && "$sub" != add-generic-password ]] && want_value=1
  [[ "$a" == *.keychain-db ]] && kc="$a"
  prev="$a"
done
store="$DIR/$(basename "${kc%.keychain-db}").store"
case "$sub" in
  find-generic-password)
    grep -q "^${name}=" "$store" 2>/dev/null || exit 44
    # FAKE_LOCKED names tiers that are locked until unlock-keychain opens them
    # (only with an empty password, unless FAKE_HAS_PASSWORD names the tier too)
    t="$(basename "${kc%.keychain-db}")"
    if (( want_value )) && [[ " ${FAKE_LOCKED:-} " == *" $t "* ]] && [[ ! -f "$DIR/$t.open" ]]; then exit 36; fi
    # `(( 0 ))` exits 1, and as the last command in this branch that would make a
    # successful lookup look like a failure. Guard it with an explicit exit.
    if (( want_value )); then sed -n "s/^${name}=//p" "$store"; fi
    exit 0
    ;;
  add-generic-password)
    # FAKE_WRITE_FAILS_IN names a tier whose writes fail (disk full, locked, ...).
    [[ "$(basename "${kc%.keychain-db}")" == "${FAKE_WRITE_FAILS_IN:-}" ]] && { echo "security: write failed" >&2; exit 36; }
    # FAKE_CORRUPT_WRITE stores something else, to prove verification catches it.
    [[ -n "${FAKE_CORRUPT_WRITE:-}" ]] && value="mangled"
    grep -v "^${name}=" "$store" > "$store.t" 2>/dev/null || true; mv "$store.t" "$store" 2>/dev/null || : > "$store"
    echo "${name}=${value}" >> "$store"
    ;;
  delete-generic-password)
    grep -v "^${name}=" "$store" > "$store.t" 2>/dev/null || true; mv "$store.t" "$store"
    ;;
  create-keychain) : > "$kc"; exit 0 ;;
  unlock-keychain)
    [[ "${FAKE_UNLOCK_FAILS:-0}" == 1 ]] && { echo "SecKeychainUnlock failed" >&2; exit 51; }
    t="$(basename "${kc%.keychain-db}")"
    [[ " ${FAKE_HAS_PASSWORD:-} " == *" $t "* ]] && exit 51
    : > "$DIR/$t.open"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/security"

run() {
  ( export SECRETS_HELPER_CONFIG="$WORK/config.sh" \
           SECRETS_KEYCHAIN_DIR="$WORK/keychains" \
           FAKE_KC_DIR="$WORK/keychains" \
           FAKE_ARGV_LOG="$WORK/argv.log" \
           PATH="$WORK:$PATH"
    ./bin/secrets "$@" </dev/null 2>&1 )
}
# run_in INPUT args...: the same, with INPUT on stdin (not a terminal)
run_in() {
  local input="$1"; shift
  ( export SECRETS_HELPER_CONFIG="$WORK/config.sh" \
           SECRETS_KEYCHAIN_DIR="$WORK/keychains" \
           FAKE_KC_DIR="$WORK/keychains" \
           FAKE_ARGV_LOG="$WORK/argv.log" \
           PATH="$WORK:$PATH"
    printf '%s' "$input" | ./bin/secrets "$@" 2>&1 )
}

reset() {
  rm -rf "$WORK/keychains"; mkdir -p "$WORK/keychains"
  for t in dev-secrets prod-secrets quarantine; do
    : > "$WORK/keychains/$t.keychain-db"
    : > "$WORK/keychains/$t.store"
  done
  echo "NAS_PASSWORD=hunter2" > "$WORK/keychains/dev-secrets.store"
}
val() { sed -n "s/^$2=//p" "$WORK/keychains/$1.store" 2>/dev/null; }

echo "== secrets move =="

reset
out=$(run move dev-secrets prod-secrets NAS_PASSWORD)
contains "reports the move by name" "$out" "NAS_PASSWORD"
lacks    "never prints the value"   "$out" "hunter2"
check    "lands in the target tier" "$(val prod-secrets NAS_PASSWORD)" "hunter2"
check    "and is gone from the source" "$(val dev-secrets NAS_PASSWORD)" ""

reset
out=$(FAKE_WRITE_FAILS_IN=prod-secrets run move dev-secrets prod-secrets NAS_PASSWORD 2>&1 || true)
check    "a failed write keeps the original" "$(val dev-secrets NAS_PASSWORD)" "hunter2"
contains "and says the move failed" "$out" "not moved"

reset
out=$(FAKE_CORRUPT_WRITE=1 run move dev-secrets prod-secrets NAS_PASSWORD 2>&1 || true)
check    "a corrupted copy keeps the original" "$(val dev-secrets NAS_PASSWORD)" "hunter2"
# _store reads the copy back itself, so a mangled write is caught at the write
contains "and reports that nothing moved" "$out" "not moved"

reset
out=$(run move dev-secrets prod-secrets NOPE 2>&1 || true)
contains "a missing source key is reported" "$out" "not found"

reset
echo "NAS_PASSWORD=other" > "$WORK/keychains/prod-secrets.store"
out=$(run move dev-secrets prod-secrets NAS_PASSWORD 2>&1 || true)
contains "an existing target key stops the move" "$out" "already"
check    "leaving both sides untouched" "$(val prod-secrets NAS_PASSWORD)" "other"
check    "including the source"          "$(val dev-secrets NAS_PASSWORD)" "hunter2"

reset
echo "NAS_PASSWORD=other" > "$WORK/keychains/prod-secrets.store"
out=$(run move dev-secrets prod-secrets NAS_PASSWORD --force)
check "--force overwrites the target" "$(val prod-secrets NAS_PASSWORD)" "hunter2"
check "and still clears the source"   "$(val dev-secrets NAS_PASSWORD)" ""

reset
out=$(run move dev-secrets quarantine NAS_PASSWORD)
check "moving INTO quarantine is allowed — that is the point" "$(val quarantine NAS_PASSWORD)" "hunter2"

reset
out=$(run move dev-secrets dev-secrets NAS_PASSWORD 2>&1 || true)
contains "refuses a move to the same tier" "$out" "same tier"

reset
out=$(run move dev-secrets nonexistent NAS_PASSWORD 2>&1 || true)
contains "rejects an unknown target tier" "$out" "unknown tier"
check    "and keeps the original"          "$(val dev-secrets NAS_PASSWORD)" "hunter2"

reset
out=$(FAKE_UNLOCK_FAILS=1 run move dev-secrets prod-secrets NAS_PASSWORD 2>&1 || true)
check "a target that will not unlock keeps the original" "$(val dev-secrets NAS_PASSWORD)" "hunter2"

echo "== values never reach an argument list =="

reset; : > "$WORK/argv.log"
run move dev-secrets prod-secrets NAS_PASSWORD >/dev/null
lacks "move: the value is in no security argument list" "$(cat "$WORK/argv.log")" "hunter2"

echo "== secrets add =="

reset; : > "$WORK/argv.log"
v='s3cr3t "with" spaces\and $(signs)'
out=$(run_in "$v" add dev-secrets NEW_TOKEN)
contains "reports the name"                  "$out" "Added 'NEW_TOKEN'"
lacks    "never prints the value"            "$out" "s3cr3t"
check    "stores the value from stdin exactly" "$(val dev-secrets NEW_TOKEN)" "$v"
lacks    "the value is in no security argument list" "$(cat "$WORK/argv.log")" "s3cr3t"
out=$(run add dev-secrets OTHER visible-value 2>&1 || true)
contains "a value as an argument is refused"  "$out" "no longer an argument"
check    "and nothing is stored"             "$(val dev-secrets OTHER)" ""
out=$(run_in "" add dev-secrets EMPTY 2>&1 || true)
contains "an empty value is refused"         "$out" "empty value"
reset
out=$(FAKE_WRITE_FAILS_IN=dev-secrets run_in "x" add dev-secrets FAILS 2>&1 || true)
contains "a failed write is reported"        "$out" "could not store"

echo "== secrets get on a locked tier =="

reset
out=$(FAKE_LOCKED="dev-secrets" run get dev-secrets NAS_PASSWORD)
check    "an auto-unlock tier locked after a reboot is opened and read" "$out" "hunter2"
reset
out=$(FAKE_LOCKED="dev-secrets" FAKE_HAS_PASSWORD="dev-secrets" run get dev-secrets NAS_PASSWORD 2>&1 || true)
contains "a tier that will not open says how to open it" "$out" "unlock dev-secrets"
lacks    "and prints no value"                "$out" "hunter2"
echo "OTHER=x" > "$WORK/keychains/prod-secrets.store"
out=$(FAKE_LOCKED="prod-secrets" run get prod-secrets OTHER 2>&1 || true)
contains "a session tier is never opened by get" "$out" "is locked"
check    "and stays closed"                      "$([ -f "$WORK/keychains/prod-secrets.open" ] && echo open || echo closed)" "closed"
out=$(run get dev-secrets NOPE 2>&1 || true)
contains "a missing item is called missing"      "$out" "not found"

echo "== secrets create-tier =="

reset; rm -f "$WORK/keychains/quarantine.keychain-db"; : > "$WORK/argv.log"
out=$(run_in 'tier "pw" 42' create-tier quarantine 2>&1)
check "creates the keychain"                 "$([ -f "$WORK/keychains/quarantine.keychain-db" ] && echo yes)" "yes"
lacks "the keychain password is in no argument list" "$(cat "$WORK/argv.log")" "tier"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
