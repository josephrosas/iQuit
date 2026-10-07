#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/.build-toolchain"
clang -c -arch arm64 -mmacosx-version-min=14.0 \
  "$ROOT/Scripts/package-description-shim.s" \
  -o "$ROOT/.build-toolchain/package-description-shim.o"

export SWIFT_EXEC="$ROOT/Scripts/swiftc-manifest-fix"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" || ! -f "$ROOT/Sources/iQuit/Assets/AppLogo.png" ]]; then
  echo "Generating app icon…"
  swift "$ROOT/Scripts/make-icon.swift"
fi

CONFIG="${1:-release}"
echo "Building iQuit ($CONFIG)…"
swift build -c "$CONFIG" --product iQuit

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/iQuit"
APP="$ROOT/dist/iQuit.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/iQuit"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ROOT/Sources/iQuit/Assets/AppLogo.png" "$APP/Contents/Resources/AppLogo.png"

chmod +x "$APP/Contents/MacOS/iQuit"

codesign --force --deep --sign - --entitlements "$ROOT/Resources/iQuit.entitlements" "$APP"

echo "Built $APP"
echo "Open with: open \"$APP\""
echo "CLI: \"$APP/Contents/MacOS/iQuit\" --help"
