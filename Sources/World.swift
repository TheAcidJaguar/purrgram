// DesktopCat — the screen and other apps' windows the cat lives among.

import Cocoa

// MARK: - World (screen + other apps' windows)

struct Plat {
    let id: CGWindowID
    let rect: CGRect
    let order: Int  // 0 = frontmost
    var top: CGFloat { rect.maxY }
}

final class World {
    var all: [Plat] = []    // every normal window, front to back
    var stand: [Plat] = []  // windows whose top edge the cat can stand on
    var screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    var vis = CGRect(x: 0, y: 0, width: 1440, height: 875)
    var bowlRect = CGRect.zero
    var floorY: CGFloat { vis.minY }
    var foodX: CGFloat { bowlRect.minX + BowlView.foodLX }
    var waterX: CGFloat { bowlRect.minX + BowlView.waterLX }
    let pid = ProcessInfo.processInfo.processIdentifier
    let ignoredOwners: Set<String> = ["Dock", "Window Server", "Control Center", "Notification Center", "WindowManager", "Spotlight", "Screenshot"]

    func refresh() {
        guard let main = NSScreen.screens.first else { return }
        screen = main.frame; vis = main.visibleFrame
        bowlRect = CGRect(x: (vis.maxX - 150).rounded(), y: vis.minY.rounded(), width: BowlView.size.width, height: BowlView.size.height)
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        var list: [Plat] = []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != self.pid,
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
            if let a = w[kCGWindowAlpha as String] as? Double, a < 0.1 { continue }
            if ignoredOwners.contains(w[kCGWindowOwnerName as String] as? String ?? "") { continue }
            if r.width < 140 || r.height < 90 { continue }
            let rect = CGRect(x: r.minX, y: screen.height - r.maxY, width: r.width, height: r.height)
            list.append(Plat(id: id, rect: rect, order: list.count))
        }
        all = list
        stand = list.filter { p in
            let lo = max(p.rect.minX, vis.minX), hi = min(p.rect.maxX, vis.maxX)
            return hi - lo > 120 && p.top > floorY + 70 && p.top + 62 < vis.maxY
        }
    }

    func plat(_ id: CGWindowID) -> Plat? { all.first { $0.id == id } }

    /// Is the top edge of `p` at `x` free of windows stacked in front of it?
    func topVisible(_ p: Plat, _ x: CGFloat) -> Bool {
        for o in all where o.order < p.order {
            for dx in [-26.0, 0, 26] as [CGFloat] where o.rect.contains(P(x + dx, p.top + 14)) { return false }
        }
        return true
    }
}
