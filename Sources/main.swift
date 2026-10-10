// DesktopCat — a little pixel cat that lives on your Mac desktop.
// Click to pet, double-click to shoo, drag to pick up. Keep the bowls full!

import Cocoa

// MARK: - Entry

let args = CommandLine.arguments
if args.contains("--selftest") { exit(selfTest()) }
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count { renderSheet(args[i + 1]); exit(0) }
if let i = args.firstIndex(of: "--closeup"), i + 1 < args.count {
    renderCloseup(args[i + 1], coat: i + 2 < args.count ? Int(args[i + 2]) ?? 0 : 0); exit(0)
}
if let i = args.firstIndex(of: "--menuicon"), i + 1 < args.count {
    renderPNG(size: CGSize(width: 90, height: 22), scale: 8, to: args[i + 1]) { ctx in
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 90, height: 22).fill()
        MenuIcon.image().draw(in: NSRect(x: 3, y: 3, width: 16, height: 16))
    }
    exit(0)
}
if let i = args.firstIndex(of: "--gif"), i + 2 < args.count {
    renderGIF(args[i + 1], args[i + 2], coat: i + 3 < args.count ? Int(args[i + 3]) ?? 0 : 0); exit(0)
}
if let i = args.firstIndex(of: "--icon"), i + 1 < args.count { renderIcon(args[i + 1]); exit(0) }
if let i = args.firstIndex(of: "--export-frames"), i + 1 < args.count { exportFrames(args[i + 1]); exit(0) }
if let i = args.firstIndex(of: "--hero"), i + 1 < args.count { renderHero(args[i + 1]); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
