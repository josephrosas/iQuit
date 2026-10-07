#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/.build-toolchain"
clang -c -arch arm64 -mmacosx-version-min=14.0 \
  "$ROOT/Scripts/package-description-shim.s" \
  -o "$ROOT/.build-toolchain/package-description-shim.o"

# Only the Package.swift manifest needs the shim; pointing SWIFT_EXEC at it makes
# SwiftPM derive the toolchain root from the shim's path and lose Testing.framework.
export SWIFT_EXEC_MANIFEST="$ROOT/Scripts/swiftc-manifest-fix"

# Command Line Tools ship Swift Testing but not XCTest.
# The CLT macro plugin server occasionally fails to come up on the first compile
# ("plugin for module 'TestingMacros' not found"); retry once when that happens.
LOG="$(mktemp -t iquit-test)"
trap 'rm -f "$LOG"' EXIT
for attempt in 1 2; do
  if swift test --disable-xctest "$@" 2>&1 | tee "$LOG"; then
    exit 0
  fi
  if ! grep -q "plugin for module 'TestingMacros' not found" "$LOG"; then
    exit 1
  fi
  echo "Macro plugin was unavailable; retrying…" >&2
done
exit 1
