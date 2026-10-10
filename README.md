# Purrgram

Purrgram is a free Mac app that gives you a pixel-art pet cat that lives right on your desktop, alongside your windows while you work.

The cat has a mind of its own. It strolls along the bottom of your screen, hops up onto your open windows (and rides along when you drag them), naps, grooms, stretches, gets the zoomies, and squeezes underneath big windows to hide. Click it to pet it, drag it to pick it up, or toss it a ball of yarn and watch it play.

It also needs looking after, a bit like a Tamagotchi. Keep its food and water bowls full, give it attention, brush its coat and hand out the occasional treat, and it stays happy. Pick from 12 coats, add a collar, and choose its mood. Purrgram lives in your menu bar, lets your clicks pass straight through to your work, is light on battery, and runs entirely on your Mac without going online.

![Purrgram](hero.png)

| | | |
|---|---|---|
| ![Catching a window edge](edge-catch-climb.gif) | ![Scratching a window](scratching.gif) | ![Hide Everything](hide-everything.gif) |

**Download:** grab `Purrgram.dmg` from the [latest release](../../releases/latest).
Needs macOS 12 or newer. Works on Apple Silicon and Intel Macs.

## Install

1. Open `Purrgram.dmg` and drag **Purrgram** onto the **Applications** folder next to it. Then eject the disk image.
2. Open Purrgram from Applications. macOS will say Apple couldn't verify it, because it isn't from the App Store.
   Click **Done** (not "Move to Trash").
3. Go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Purrgram, and confirm.
   (On macOS 14 or older you can instead right-click the app → **Open** → **Open**.)
4. Name your cat!

You only do steps 2–3 once.

### Check the download is genuine (optional)

Each release lists a SHA-256 fingerprint for the DMG. In Terminal:

```bash
shasum -a 256 ~/Downloads/Purrgram.dmg
```

The result should match the fingerprint on the release page exactly.

## Controls

- **Click** the cat to pet it (they purr, but don't overdo it)
- **Double-click** to shoo it out of the way
- **Drag** to pick it up and drop it on a window
- **Click the bowls** (bottom-right corner) to fill food and water
- The **cat face in the menu bar** has stats, treats, yarn, mice, brushing, coats, collars, moods, Hide Everything (⌘H) and Settings (⌘,)

The cat's needs only change while your Mac is awake and Purrgram is running. Close the lid and everything pauses.

## Privacy

Purrgram runs entirely on your Mac. It has no network code, so it never connects to the internet and sends nothing anywhere. It doesn't ask for any permissions. It reads where windows are on screen (not what's in them) so the cat can jump on them, and it only writes its own save file in `~/Library/Application Support/DesktopCat/`.

## Build from source

Requires the Xcode command line tools (`xcode-select --install`). Pure Swift with AppKit, no dependencies.

```bash
./build.sh
```

This compiles a universal app, runs a self-test, and writes `build/Purrgram.app`, `build/Purrgram.dmg`, `build/Purrgram.zip` and `build/SHA256.txt`. A copy you build yourself opens without any security warning.
