#!/bin/bash
# Builds "Press Paws.app" (Apple Silicon + Intel) and a shareable "Press Paws.zip".
# (The executable, bundle ID and save folder keep the old DesktopCat name so existing cats carry over.)
set -euo pipefail
cd "$(dirname "$0")"

NAME="Press Paws"
APP="build/$NAME.app"
rm -rf build && mkdir -p build

echo "• Compiling…"
swiftc -O -swift-version 5 -target arm64-apple-macos12  Sources/*.swift -o build/cat-arm64
swiftc -O -swift-version 5 -target x86_64-apple-macos12 Sources/*.swift -o build/cat-x86_64
lipo -create build/cat-arm64 build/cat-x86_64 -output build/DesktopCat

echo "• Running self-test…"
if [ "$(uname -m)" = "arm64" ]; then build/cat-arm64 --selftest; else build/cat-x86_64 --selftest; fi

echo "• Assembling app bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv build/DesktopCat "$APP/Contents/MacOS/DesktopCat"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Press Paws</string>
  <key>CFBundleDisplayName</key><string>Press Paws</string>
  <key>CFBundleIdentifier</key><string>com.desktopcat.app</string>
  <key>CFBundleExecutable</key><string>DesktopCat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "• Drawing the app icon…"
"$APP/Contents/MacOS/DesktopCat" --icon build/icon.png
ICONSET=build/AppIcon.iconset && mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"

echo "• Signing (ad-hoc)…"
codesign --force --deep -s - "$APP"

echo "• Zipping for friends…"
mkdir -p "build/share/$NAME"
cp -R "$APP" "build/share/$NAME/"
cp "READ ME FIRST.txt" "build/share/$NAME/"
ditto -c -k --norsrc --noextattr --keepParent "build/share/$NAME" "build/$NAME.zip"
rm -rf build/cat-* "$ICONSET" build/share

echo "✓ Done: $APP and build/$NAME.zip"
