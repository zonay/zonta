#!/bin/zsh
# Builds build/Zonta.app: compile, icon, sign.
# Pass an identity to override the default certificate.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Zonta.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
# A stable signing identity keeps TCC grants (microphone, accessibility, local
# network) across rebuilds. Pass one as the first argument, or set SIGN_IDENTITY.
# With neither, an ad-hoc signature is used: free, but macOS treats every
# rebuild as a new app and asks for the permissions again.
IDENTITY="${1:-${SIGN_IDENTITY:-}}"

if [[ -n "$IDENTITY" ]]; then
  if ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "ERROR: signing identity not found: $IDENTITY" >&2
    echo "Pass a valid one: ./build.sh 'Developer ID Application: Name (TEAMID)'" >&2
    exit 1
  fi
else
  IDENTITY="-"
  echo "==> no signing identity given; using an ad-hoc signature" >&2
fi

mkdir -p "$BIN" "$RES" build

echo "==> compiling"
swiftc -O -parse-as-library -module-cache-path "$PWD/build/ModuleCache" \
  -framework AppKit -framework SwiftUI -framework AVFoundation \
  -framework ApplicationServices -framework CoreGraphics -framework Network \
  -o "$BIN/Zonta" \
  Zonta/*.swift

echo "==> icon"
swiftc -O -parse-as-library -module-cache-path "$PWD/build/ModuleCache" \
  -framework AppKit -framework CoreGraphics -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -o build/icongen Tools/IconGen.swift Zonta/Mark.swift
rm -rf build/Zonta.iconset
./build/icongen build/Zonta.iconset
iconutil -c icns build/Zonta.iconset -o build/AppIcon.icns
cp build/AppIcon.icns "$RES/AppIcon.icns"

cp Zonta/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> signing with $IDENTITY"
SIGN_ARGS=(--force --sign "$IDENTITY" --entitlements Zonta/Zonta.entitlements)
# Hardened runtime is required for notarization and is only meaningful with a
# real Developer ID identity; ad-hoc development builds stay as they are.
if [[ "$IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "==> signed with $(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1)"
