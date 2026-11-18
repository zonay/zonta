#!/bin/zsh
# Builds, installs into /Applications, and launches Zonta.
#
# The install step matters: macOS only grants UNUserNotificationCenter
# authorization to apps in a standard location. An app run straight from
# build/ gets UNErrorDomain 1 ("Notifications are not allowed") with no
# prompt, so running in place is not enough.
set -euo pipefail
cd "$(dirname "$0")"

DEST="/Applications/Zonta.app"

./build.sh

pkill -x Zonta 2>/dev/null || true
sleep 0.3

# Keep one copy of the original installed app before the first replacement.
BACKUP="build/Zonta-installed-backup.app"
if [[ -d "$DEST" && ! -d "$BACKUP" ]]; then
  mkdir -p build
  ditto "$DEST" "$BACKUP"
  echo "backed up the installed app to $BACKUP"
fi
if [[ -d "$DEST" ]]; then
  rm -rf "$DEST"
fi

# ditto preserves the code signature and extended attributes.
ditto build/Zonta.app "$DEST"
codesign --verify --deep --strict "$DEST"

open "$DEST"
echo "launched $DEST"
