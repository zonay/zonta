#!/bin/zsh
# Builds and launches the app for local use.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

pkill -x Zonta 2>/dev/null || true
sleep 0.3
open build/Zonta.app
echo "launched build/Zonta.app"
