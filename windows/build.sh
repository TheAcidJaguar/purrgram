#!/bin/bash
# Builds Purrgram for Windows (Lite) from a Mac: renders every animation with the Mac app's own drawing code,
# bakes the frames into a small .NET Framework 4.8 exe (built into Windows 10/11, nothing to install),
# and zips it as build/Purrgram-Windows.zip. Needs the .NET SDK (`brew install dotnet`).
set -euo pipefail
cd "$(dirname "$0")"
export DOTNET_ROOT="${DOTNET_ROOT:-/opt/homebrew/opt/dotnet/libexec}"

echo "• Rendering frames with the Mac renderer…"
mkdir -p build && rm -rf build/frames Assets && mkdir -p Assets
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos12" ../Sources/*.swift -o build/render
build/render --export-frames build/frames
for d in build/frames/cats/*/; do
  coat=$(basename "$d")
  for f in "$d"*.png; do cp "$f" "Assets/cat_${coat}_$(basename "$f")"; done
done
for f in build/frames/bowls/*.png; do cp "$f" "Assets/bowl_$(basename "$f")"; done

echo "• Drawing the icon…"
build/render --icon build/icon.png
for s in 16 24 32 48 64 256; do sips -z $s $s build/icon.png --out build/icon_$s.png >/dev/null; done
python3 - <<'PY'
import struct
sizes = [16, 24, 32, 48, 64, 256]
blobs = [open(f"build/icon_{s}.png", "rb").read() for s in sizes]
out = struct.pack("<HHH", 0, 1, len(sizes)); off = 6 + 16 * len(sizes)
for s, b in zip(sizes, blobs):
    out += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(b), off); off += len(b)
open("Assets/icon.ico", "wb").write(out + b"".join(blobs))
PY
cp build/icon_256.png Assets/icon.png   # the tray icon is drawn from this

echo "• Compiling…"
dotnet build -c Release -nologo -v q -o build/out

echo "• Zipping…"
rm -rf build/share && mkdir -p build/share/Purrgram
cp build/out/Purrgram.exe build/share/Purrgram/
cp "READ ME FIRST.txt" build/share/Purrgram/
(cd build/share && rm -f ../Purrgram-Windows.zip && zip -qr ../Purrgram-Windows.zip Purrgram)
rm -rf build/share
echo "✓ Done: windows/build/Purrgram-Windows.zip ($(du -h build/Purrgram-Windows.zip | cut -f1))"
