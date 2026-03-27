#!/bin/bash
set -euo pipefail

# Usage: scripts/create-dmg.sh <path-to-Looper.app> <output-dir>
APP_PATH="${1:?Usage: create-dmg.sh <Looper.app> <output-dir>}"
OUTPUT_DIR="${2:-.}"
DMG_PATH="$OUTPUT_DIR/Looper.dmg"

# Remove existing DMG if present
rm -f "$DMG_PATH"

create-dmg \
  --volname "Looper" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 80 \
  --icon "Looper.app" 180 170 \
  --app-drop-link 480 170 \
  --hide-extension "Looper.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"
