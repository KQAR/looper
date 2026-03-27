#!/bin/bash
set -euo pipefail

# Usage: scripts/create-dmg.sh <path-to-Looper.app> <output-dir>
APP_PATH="${1:?Usage: create-dmg.sh <Looper.app> <output-dir>}"
OUTPUT_DIR="${2:-.}"

rm -f "$OUTPUT_DIR"/Looper*.dmg

mise exec -- create-dmg "$APP_PATH" "$OUTPUT_DIR" \
  --overwrite \
  --dmg-title="Looper"

# Rename "Looper X.Y.Z.dmg" → "Looper.dmg"
for f in "$OUTPUT_DIR"/Looper*.dmg; do
  if [ "$f" != "$OUTPUT_DIR/Looper.dmg" ]; then
    mv "$f" "$OUTPUT_DIR/Looper.dmg"
  fi
done
