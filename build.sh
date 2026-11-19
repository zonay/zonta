#!/bin/zsh
# Builds build/Zonta.app: compile, icon, sign.
# Pass an identity to override the default certificate.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Zonta.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
# A stable signing identity keeps TCC grants (microphone, accessibility, local
# network) across rebuilds. Ad-hoc signing makes macOS treat every rebuild as a
# new app, so the permission prompts return each time. The default matches the
# installed app's identity and bundle id, so dev inherits its grants/settings.
# Override with the first argument or SIGN_IDENTITY; pass "-" for ad-hoc.
DEFAULT_IDENTITY="Developer ID Application: ZAFER ONAY (TP7C938GZF)"
IDENTITY="${1:-${SIGN_IDENTITY:-$DEFAULT_IDENTITY}}"

if [[ "$IDENTITY" == "-" ]]; then
  echo "==> ad-hoc signature requested" >&2
elif [[ -n "$IDENTITY" ]]; then
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
  -framework UserNotifications \
  -framework CoreAudio -framework AudioToolbox \
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

# A different bundle id or team changes the designated requirement, which
# makes macOS treat every rebuild as a brand-new app and re-ask every TCC
# grant (microphone, accessibility, local network, notifications). Fail the
# build instead of silently producing an app that prompts again.
if [[ "$IDENTITY" != "-" ]]; then
  BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Zonta/Info.plist)"
  TEAM="$(printf '%s' "$IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
  REQ="$(codesign -d --requirements - "$APP" 2>&1)"
  if [[ -z "$TEAM" || "$REQ" != *"identifier \"$BUNDLE\""* || "$REQ" != *"$TEAM"* ]]; then
    echo "ERROR: signature drift — Info.plist is $BUNDLE but the signature is for $TEAM." >&2
    echo "       TCC grants would reset on every rebuild. Fix the identity/bundle id." >&2
    exit 1
  fi
  echo "==> stable identity verified: $BUNDLE / team $TEAM"
else
  echo "==> WARNING: ad-hoc build — macOS will re-ask permissions after this rebuild." >&2
fi
