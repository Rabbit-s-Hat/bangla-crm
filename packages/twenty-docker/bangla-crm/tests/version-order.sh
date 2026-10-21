#!/usr/bin/env bash
# Checks version_lt from bangla-crm.sh against tests/version-order.txt.
# Run: bash tests/version-order.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# Load only the function (sourcing the whole script would run its main command).
eval "$(sed -n '/^version_lt() {/,/^}/p' "$here/../bangla-crm.sh")"
fails=0
while read -r a b want; do
  case "$a" in ''|'#'*) continue ;; esac
  if version_lt "$a" "$b"; then got=yes; else got=no; fi
  if [ "$got" = "$want" ]; then echo "  ok   $a < $b : $got"; else echo "  FAIL $a < $b : got $got, want $want"; fails=$((fails + 1)); fi
done < "$here/version-order.txt"
[ "$fails" -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
echo "All version-order checks passed (bash)."
