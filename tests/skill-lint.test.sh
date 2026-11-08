#!/usr/bin/env bash
# skill-lint.test.sh — the agent skill must never teach an agent to show a
# secret or put one in an argument list (security review 2026-10-01, fix 9).
# Checks every copy of the skill: the source and the per-agent versions.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
files=(agent-skill/secrets-helper.md agent-skill/claude-code/SKILL.md agent-skill/cursor/secrets-helper.mdc)
rule() { # rule <description> <extended regex>; a line saying "refused" explains, not teaches
	local hits; hits=$(grep -nE "$2" "${files[@]}" | grep -v "refused" || true)
	if [[ -z "$hits" ]]; then PASS=$((PASS+1)); echo "  ok   $1"
	else FAIL=$((FAIL+1)); echo "  FAIL $1"; printf '       %s\n' "$hits"; fi
}
echo "== agent skill lint =="
rule "no bare 'secrets get' that prints the value"    '^[[:space:]]*secrets get '
rule "no prefix of a value printed"                   '\$\{[A-Za-z_]+:[0-9]+(:[0-9]+)?\}'
rule "no value given to 'secrets add' as an argument" 'secrets add [^ ]+ [^ ]+ +(<[A-Za-z]|[a-z_]+[0-9]|ghp_|sk-|"[^<])'
rule "no token in a curl -H argument"                 '\-H "Authorization[^"]*\$\(secrets get'
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
