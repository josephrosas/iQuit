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
swift test --disable-xctest "$@"
