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

echo "• Making the drag-to-Applications disk image…"
DMG="build/$NAME.dmg"; RW=build/rw.dmg; STAGE=build/dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "READ ME FIRST.txt" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
# Lay out the window: app on the left, Applications on the right. Needs one-time permission to control
# Finder; if that's refused the image still works, just with Finder's default layout.
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
osascript >/dev/null 2>&1 <<APPLESCRIPT || echo "  (couldn't arrange the window — using Finder's default layout)"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 470}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set position of item "$NAME.app" of container window to {140, 150}
    set position of item "Applications" of container window to {420, 150}
    set position of item "READ ME FIRST.txt" of container window to {280, 290}
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$MNT"
rm -f "$DMG"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW" "$STAGE"
codesign --force -s - "$DMG"

# Fingerprints: send these to friends separately (e.g. by text) so they can check the download is really yours.
( cd build && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256.txt )

echo "✓ Done: $APP, build/$NAME.zip and $DMG"
echo "  Fingerprints (build/SHA256.txt):"; sed 's/^/    /' build/SHA256.txt
