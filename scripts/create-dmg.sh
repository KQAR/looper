#!/bin/bash
set -euo pipefail

# Usage: scripts/create-dmg.sh <path-to-Looper.app> <output-dir>
APP_PATH="${1:?Usage: create-dmg.sh <Looper.app> <output-dir>}"
OUTPUT_DIR="${2:-.}"

rm -f "$OUTPUT_DIR"/Looper*.dmg

# create-dmg exits 2 when code signing identity is not found;
# the DMG is still created successfully, just unsigned.
set +e
mise exec -- create-dmg "$APP_PATH" "$OUTPUT_DIR" \
  --overwrite \
  --dmg-title="Looper"
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 2 ]; then
  exit $EXIT_CODE
fi

# Rename "Looper X.Y.Z.dmg" → "Looper.dmg"
for f in "$OUTPUT_DIR"/Looper*.dmg; do
  if [ "$f" != "$OUTPUT_DIR/Looper.dmg" ]; then
    mv "$f" "$OUTPUT_DIR/Looper.dmg"
  fi
done
