#!/bin/bash
# MemScope.app paketini oluşturur.
#   ./build.sh           → build/MemScope.app
#   ./build.sh install   → derler, /Applications/MemScope.app olarak kurar ve başlatır
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

if [ ! -f Resources/AppIcon.icns ]; then
  TMP=$(mktemp -d)
  swift tools/make_icon.swift "$TMP/icon.png"
  mkdir -p "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi

APP=build/MemScope.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MemScope "$APP/Contents/MacOS/MemScope"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "✅ $APP hazır"

if [ "${1:-}" = "install" ]; then
  pkill -x MemScope 2>/dev/null || true
  sleep 1
  rm -rf /Applications/MemScope.app
  cp -R "$APP" /Applications/MemScope.app
  open /Applications/MemScope.app
  echo "✅ /Applications/MemScope.app kuruldu ve başlatıldı"
fi
