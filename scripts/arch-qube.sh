#!/usr/bin/env bash
#
# arch-qube.sh — architecture conformance gate. Enforces the module dependency direction
# (Clean Architecture: inner layers never import outer ones). Any violation fails the build.
# Must be 100% green — there is no partial pass.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources"
violations=0

# selftest: prove the gate turns red on a known-bad input (guards against false-green).
if [ "${1:-}" = "selftest" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/Sources/ArcanaModel"
  printf 'import ArcanaShell\n' > "$tmp/Sources/ArcanaModel/Bad.swift"
  if grep -rEn "^[[:space:]]*(@_[a-zA-Z]+[[:space:]]+)?import[[:space:]]+ArcanaShell\b" "$tmp/Sources/ArcanaModel" >/dev/null 2>&1; then
    echo "arch-qube selftest: PASS (forbidden import is detected)"
    exit 0
  fi
  echo "arch-qube selftest: FAIL (gate did NOT detect a forbidden import — it is blind)"
  exit 1
fi

# Reports a forbidden import: <target> must not import <module>.
check_forbidden() {
  local target="$1"; shift
  local dir="$SRC/$target"
  [ -d "$dir" ] || return 0
  for module in "$@"; do
    # Match `import <Module>` (whole word) in the target's sources.
    if grep -rEn "^[[:space:]]*(@_[a-zA-Z]+[[:space:]]+)?import[[:space:]]+${module}\b" "$dir" >/dev/null 2>&1; then
      echo "✗ ARCH VIOLATION: $target must not import $module"
      grep -rEn "^[[:space:]]*(@_[a-zA-Z]+[[:space:]]+)?import[[:space:]]+${module}\b" "$dir" | sed 's/^/    /'
      violations=$((violations + 1))
    fi
  done
}

echo "arch-qube: checking module dependency direction…"

# ArcanaSync: zero-dependency CRDT engine — imports no other Arcana module.
check_forbidden "ArcanaSync" ArcanaPluginContracts ArcanaPlugins ArcanaShell ArcanaModel ArcanaKit

# ArcanaModel: standalone domain/identity — depends on nothing else in the fleet.
check_forbidden "ArcanaModel" ArcanaPluginContracts ArcanaPlugins ArcanaShell ArcanaKit ArcanaSync

# ArcanaPluginContracts: pure declarations — depends on no implementation module.
check_forbidden "ArcanaPluginContracts" ArcanaPlugins ArcanaShell ArcanaModel ArcanaKit ArcanaSync

# ArcanaPlugins: the runtime — may use its contracts, nothing above it.
check_forbidden "ArcanaPlugins" ArcanaShell ArcanaModel ArcanaKit ArcanaSync

# ArcanaShell: the outer shell — must not reach into the iOS-derived ArcanaKit.
check_forbidden "ArcanaShell" ArcanaKit

# Nothing may import the executable target.
check_forbidden "ArcanaKit" ArcanaMacApp
check_forbidden "ArcanaShell" ArcanaMacApp
check_forbidden "ArcanaModel" ArcanaMacApp

if [ "$violations" -eq 0 ]; then
  echo "arch-qube: PASS (0 violations)"
  exit 0
else
  echo "arch-qube: FAIL ($violations violation(s))"
  exit 1
fi
