#!/usr/bin/env bash
# Verify the exact single-file serialization used by install-service.
set -Eeuo pipefail
source "${1:-./gre.sh}"
target=${2:?Pass a temporary output filename}
render_self > "$target"
"$BASH" -n "$target"
[[ $("$BASH" "$target" --version) == 'Wilson GRE 1.0.0' ]]
[[ $("$BASH" <(render_self) --version) == 'Wilson GRE 1.0.0' ]]
printf '%s\n' 'PASS: installed source parses, runs standalone and runs via process substitution'
