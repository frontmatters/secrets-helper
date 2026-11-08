#!/usr/bin/env bash
# tests/pull.test.sh — `secrets pull` and `secrets remote-list`.
#
# The remote side is faked through SECRETS_SSH, so these run offline and never
# touch a real keychain: the fake stands in for both `ssh` and the `security`
# calls it would make. What is exercised here is the decision logic — which
# tiers may be pulled, what happens to an existing local key, and above all
# that a value never reaches stdout or a file.

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

# --- a config with the same shape as a real one -------------------------------
cat > "$WORK/config.sh" <<'EOF'
TIER_NAMES=("dev-secrets" "prod-secrets" "quarantine")
TIER_POLICIES=("2" "2" "2")
TIER_DESCS=("Dev tokens" "Infra" "LEAKED credentials pending revocation")
EOF

# --- a fake ssh -----------------------------------------------------------------
# Speaks the same protocol as the real remote side: `list` prints names, `get`
# prints one value. LOCKED=1 makes the remote keychain refuse to unlock.
cat > "$WORK/fake-ssh" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -- ]] && shift
host="$1"; shift
cmd="$*"
[[ -n "${FAKE_SSH_LOG:-}" ]] && echo "$host :: $cmd" >> "$FAKE_SSH_LOG"
if [[ "${FAKE_UNREACHABLE:-0}" == 1 ]]; then echo "ssh: connect to host $host port 22: Operation timed out" >&2; exit 255; fi
# A locked keychain: the remote script's own unlock guard fires.
if [[ "${FAKE_LOCKED:-0}" == 1 ]]; then echo "__locked" >&2; exit 4; fi
# The remote script now carries only the branch being asked for, so recognise it
# by the security subcommand it actually runs.
case "$cmd" in
  *dump-keychain*)          printf '%b' "${FAKE_LIST:-ACME_API_SECRET\nACME_API_USER\nOTHER_TOKEN\n}" ;;
  *find-generic-password*)  printf 'sup3r-s3cret-value\n' ;;
  *)                        echo "fake-ssh: unexpected command: $cmd" >&2; exit 2 ;;
esac
EOF
chmod +x "$WORK/fake-ssh"

# --- a fake `security` so no real keychain is touched ---------------------------
cat > "$WORK/security" <<'EOF'
#!/usr/bin/env bash
STORE="${FAKE_KEYCHAIN_STORE:?}"
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
if [[ "${FAKE_KEYCHAIN_MISSING:-0}" == 1 ]]; then
  echo "security: SecKeychainItemCreateFromContent (kc): User interaction is not allowed." >&2
  exit 36
fi
case "$1" in
  find-generic-password)
    for a in "$@"; do [[ "$prev" == "-s" ]] && name="$a"; prev="$a"; done
    grep -q "^${name}=" "$STORE" 2>/dev/null || exit 44
    [[ " $* " == *" -w "* ]] && sed -n "s/^${name}=//p" "$STORE"
    ;;
  add-generic-password)
    for a in "$@"; do
      [[ "$prev" == "-s" ]] && name="$a"
      [[ "$prev" == "-w" ]] && value="$a"
      prev="$a"
    done
    if [[ "${FAKE_STORE_FAILS:-}" == "$name" ]]; then echo "security: could not write" >&2; exit 36; fi
    grep -v "^${name}=" "$STORE" > "$STORE.tmp" 2>/dev/null || true
    mv "$STORE.tmp" "$STORE"
    echo "${name}=${value:-}" >> "$STORE"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$WORK/security"

run() {
  ( export SECRETS_HELPER_CONFIG="$WORK/config.sh" \
           SECRETS_SSH="$WORK/fake-ssh" \
           SECRETS_KEYCHAIN_DIR="$WORK/keychains" \
           FAKE_KEYCHAIN_STORE="$WORK/store" \
           PATH="$WORK:$PATH"
    ./bin/secrets "$@" </dev/null 2>&1 )
}

mkdir -p "$WORK/keychains"
: > "$WORK/keychains/dev-secrets.keychain-db"      # tier exists on this machine
: > "$WORK/keychains/prod-secrets.keychain-db"
: > "$WORK/store"

echo "== secrets pull =="

out=$(run pull host-b dev-secrets ACME_API_USER)
contains "reports the key by name" "$out" "ACME_API_USER"
lacks    "never prints the value"  "$out" "sup3r-s3cret-value"
check    "stores it locally" "$(sed -n 's/^ACME_API_USER=//p' "$WORK/store")" "sup3r-s3cret-value"

out=$(run pull host-b dev-secrets ACME_API_USER)
contains "skips a key that already exists" "$out" "skipped"

out=$(run pull host-b dev-secrets ACME_API_USER --force)
contains "--force overwrites" "$out" "pulled"

out=$(run pull host-b 'ACME_*' 2>&1 || true)
contains "a missing tier is a usage error" "$out" "Usage"

out=$(run pull host-b quarantine SOMETHING 2>&1 || true)
contains "refuses the quarantine tier" "$out" "quarantine"
lacks    "and does not pull from it"   "$out" "pulled"

out=$(run pull host-b nonexistent-tier NAME 2>&1 || true)
contains "rejects an unknown tier" "$out" "unknown tier"

: > "$WORK/store"
out=$(run pull host-b dev-secrets 'ACME_*')
contains "a glob pulls both matches" "$out" "2 pulled"
lacks    "and leaves non-matching keys alone" "$out" "OTHER_TOKEN"

out=$(FAKE_LOCKED=1 run pull host-b dev-secrets OTHER_TOKEN 2>&1 || true)
contains "a password-protected remote tier fails clearly" "$out" "could not unlock"
lacks    "without leaking anything" "$out" "sup3r-s3cret-value"

out=$(FAKE_UNREACHABLE=1 run pull host-b dev-secrets OTHER_TOKEN 2>&1 || true)
contains "an unreachable host fails clearly" "$out" "host-b"

# A tier can be configured and still have no keychain on this machine — a fresh
# laptop is exactly that. Nothing may leave the other machine before we know we
# have somewhere to put it.
: > "$WORK/store"
mv "$WORK/keychains/dev-secrets.keychain-db" "$WORK/kc.bak"
: > "$WORK/sshlog"
out=$(FAKE_SSH_LOG="$WORK/sshlog" run pull host-b dev-secrets ACME_API_USER 2>&1 || true)
contains "non-interactive: says the tier is missing" "$out" "no keychain on this machine"
contains "and points at create-tier"                 "$out" "create-tier"
lacks    "never surfaces macOS's misleading wording" "$out" "User interaction"
check    "and nothing leaves the other machine"      "$(grep -c 'find-generic-password' "$WORK/sshlog" || true)" "0"
mv "$WORK/kc.bak" "$WORK/keychains/dev-secrets.keychain-db"

# A write that fails is not the same as a key you already had. Reporting both as
# "skipped" made a half-finished pull read like a success — which is exactly how
# one key went missing without anyone noticing.
: > "$WORK/store"
out=$(FAKE_STORE_FAILS=ACME_API_USER run pull host-b dev-secrets 'ACME_*' 2>&1 || true)
contains "a failed write is called a failure" "$out" "failed"
lacks    "and not filed under skipped"        "$out" "1 skipped"
contains "the working key still lands"        "$out" "1 pulled"

: > "$WORK/store"
( FAKE_STORE_FAILS=ACME_API_USER run pull host-b dev-secrets 'ACME_*' >/dev/null 2>&1 )
check "and the command reports failure" "$?" "1"

: > "$WORK/store"
run pull host-b dev-secrets ACME_API_USER >/dev/null 2>&1
check "a clean pull still exits 0" "$?" "0"

echo "== secrets remote-list =="
out=$(run remote-list host-b dev-secrets)
contains "lists remote names" "$out" "ACME_API_USER"
lacks    "and no values"      "$out" "sup3r-s3cret-value"

echo "== pull: names and hosts cannot inject =="

: > "$WORK/sshlog"
out=$(FAKE_SSH_LOG="$WORK/sshlog" run pull host-b dev-secrets "X'; touch $WORK/pwned; '" 2>&1 || true)
contains "a name with a quote is refused"      "$out" "cannot have"
check    "and nothing is sent to the other machine" "$(grep -c . "$WORK/sshlog" || true)" "0"
: > "$WORK/sshlog"
out=$(FAKE_LIST="GOOD_KEY\nBAD'KEY\n" FAKE_SSH_LOG="$WORK/sshlog" run pull host-b dev-secrets 'GOOD*' 2>&1 || true)
out2=$(FAKE_LIST="GOOD_KEY\nGOOD'x\n" FAKE_SSH_LOG="$WORK/sshlog" run pull host-b dev-secrets 'GOOD*' 2>&1 || true)
contains "a name the other machine sends back with a quote is skipped" "$out2" "unexpected characters"
lacks    "and is never sent in a get"          "$(cat "$WORK/sshlog")" "GOOD'x"
out=$(run pull -oProxyCommand=touch_x dev-secrets GOOD_KEY 2>&1 || true)
contains "a host that is an ssh option is refused" "$out" "not a host name"
[[ ! -e "$WORK/pwned" ]] && ok "nothing ran" || nope "a command ran"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
