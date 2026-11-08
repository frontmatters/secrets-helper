#!/usr/bin/env bash
# Runs every test (tests/*.test.sh, and the python tests in test/ when the
# cryptography package that secbak needs is installed); exits non-zero when
# one fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; rc=0
for t in "$ROOT"/tests/*.test.sh; do
	echo "== $(basename "$t")"
	bash "$t" || rc=1
done
if [ -d "$ROOT/test" ]; then
	if python3 -c 'import cryptography' 2>/dev/null; then
		echo "== python (test/)"
		(cd "$ROOT/test" && python3 -m unittest test_secbak test_secbak_cli) || rc=1
	else
		echo "SKIP python tests: the cryptography package is not installed (secbak needs it)"
	fi
fi
exit "$rc"
