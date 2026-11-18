#!/bin/zsh
# Builds a distributable Zonta.app and puts it on the Desktop.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$HOME/Desktop/Zonta"

# build.sh defaults to the stable "Developer ID Application" identity so the
# signed bundle keeps the same designated requirement across rebuilds and does
# not re-trigger macOS permission prompts. Override with the first argument or
# SIGN_IDENTITY; pass "-" only for a throwaway ad-hoc build.
SIGN_ID="${1:-${SIGN_IDENTITY:-}}"

./build.sh "$SIGN_ID"

echo "==> desktop folder"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -R build/Zonta.app "$OUT/"
cp README-Install.md "$OUT/Read Me First.md"

cat > "$OUT/Install to Applications.command" << 'INSTALL'
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
TARGET="/Applications"
if [[ -d "$HOME/Applications" ]]; then TARGET="$HOME/Applications"; fi
if [[ -w "$TARGET" ]]; then
  rm -rf "$TARGET/Zonta.app"
  cp -R "Zonta.app" "$TARGET/"
  echo "Installed to $TARGET"
  open "$TARGET/Zonta.app"
else
  echo "Cannot write to $TARGET. Copy Zonta.app there yourself."
  exit 1
fi
INSTALL
chmod +x "$OUT/Install to Applications.command"

# A zip keeps the signature intact for moving to another Mac.
ditto -c -k --keepParent "$OUT/Zonta.app" "$OUT/Zonta.zip"

# Optional notarisation. Set these to skip the Gatekeeper prompt on other Macs:
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  echo "==> notarising"
  xcrun notarytool submit "$OUT/Zonta.zip" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait
  xcrun stapler staple "$OUT/Zonta.app"
  xcrun stapler staple "$OUT/Zonta.zip"
else
  echo "==> skipping notarisation (set NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD to do it)"
fi

echo
codesign -dv --verbose=2 "$OUT/Zonta.app" 2>&1 | rg "Authority|Identifier" || true
spctl -a -t exec "$OUT/Zonta.app" 2>&1 | head -2 || true
echo "done: $OUT"
ls -la "$OUT"
