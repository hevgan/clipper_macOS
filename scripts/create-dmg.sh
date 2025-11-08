#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Clipper"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
DMG_VOL="${APP_NAME} Installer"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found at $APP_PATH. Run ./scripts/build-app.sh first." >&2
  exit 1
fi

rm -f "$DMG_PATH"
mkdir -p "$DIST_DIR"

DMG_SRC="$DIST_DIR/dmg-src"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"

cp -R "$APP_PATH" "$DMG_SRC"
ln -s /Applications "$DMG_SRC/Applications"

hdiutil create -volname "$DMG_VOL" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_PATH"

rm -rf "$DMG_SRC"

echo "DMG created at $DMG_PATH"
