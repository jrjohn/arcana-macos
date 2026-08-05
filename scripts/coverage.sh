#!/usr/bin/env bash
#
# coverage.sh — run the test suite with coverage and export an lcov report for SonarQube.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "coverage: running tests with code coverage…"
swift test --enable-code-coverage

PROFDATA="$(find .build -name 'default.profdata' -path '*codecov*' | head -1)"
XCTEST_DIR="$(find .build -name '*.xctest' -type d | head -1)"
BIN_NAME="$(basename "$XCTEST_DIR" .xctest)"
XCTEST_BIN="$XCTEST_DIR/Contents/MacOS/$BIN_NAME"

if [ -z "$PROFDATA" ] || [ ! -f "$XCTEST_BIN" ]; then
  echo "coverage: could not locate profdata / test binary" >&2
  exit 1
fi

echo "coverage: exporting lcov → coverage.lcov"
xcrun llvm-cov export \
  -format=lcov \
  -instr-profile "$PROFDATA" \
  --ignore-filename-regex='.build|Tests' \
  "$XCTEST_BIN" > coverage.lcov

echo "coverage: wrote $(wc -l < coverage.lcov) lines to coverage.lcov"
