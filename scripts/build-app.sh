#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_NAME="Clipper"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
EXECUTABLE="$BUILD_DIR/$APP_NAME"
ICON_SRC="$ROOT_DIR/src/icons/clipper-icon.png"
ICON_NAME="ClipperIcon"
ICON_ICNS="$DIST_DIR/${ICON_NAME}.icns"

command -v swift >/dev/null 2>&1 || { echo "swift is required"; exit 1; }

swift build -c release

mkdir -p "$DIST_DIR"

generate_icon() {
  if [ ! -f "$ICON_SRC" ]; then
    echo "Icon source $ICON_SRC not found. Skipping icon generation."
    return
  fi

  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "sips and iconutil are required to build the icon. Skipping icon generation."
    return
  fi

  local iconset="$DIST_DIR/${ICON_NAME}.iconset"
  rm -rf "$iconset" "$ICON_ICNS"
  mkdir -p "$iconset"

  for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    local double=$((size * 2))
    sips -z $double $double "$ICON_SRC" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$ICON_ICNS"
  rm -rf "$iconset"
}

generate_icon

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Clipper</string>
    <key>CFBundleExecutable</key>
    <string>Clipper</string>
    <key>CFBundleIdentifier</key>
    <string>dev.clipper.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>ClipperIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <string>1</string>
</dict>
</plist>
PLIST

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/Clipper"
chmod +x "$APP_DIR/Contents/MacOS/Clipper"

if [ -f "$ICON_ICNS" ]; then
  cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
fi

echo "App bundle created at $APP_DIR"
