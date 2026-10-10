// DesktopCat — the cat and bowl views.

import Cocoa

// MARK: - Views

struct RenderKey: Equatable {
    var pose: Pose, facing: CGFloat, coat: Int, collar: Int?, size: Double
}

final class CatView: NSView {
    var cat: Cat!
    var cachedKey: RenderKey?, cachedImage: CGImage?
    var lastCuts: [CGRect] = [], hadParticles = false

    func renderKey() -> RenderKey {
        RenderKey(pose: cat.pose, facing: cat.facing, coat: cat.s.coat % coats.count,
                  collar: cat.s.collarOn ? cat.s.collarHex : nil, size: cat.s.sizeMul)
    }

    /// The parts of the view currently hidden (screen edges / windows), in view coordinates.
    func cuts() -> [CGRect] {
        guard let o = window?.frame.origin else { return [] }
        return cat.occluders().map { $0.offsetBy(dx: -o.x, dy: -o.y).intersection(bounds) }.filter { !$0.isEmpty }
    }

    /// True if anything visible changed since the last draw.
    func dirty() -> Bool {
        let particles = !cat.hearts.isEmpty || !cat.fur.isEmpty || !cat.litter.isEmpty || cat.brushMode
        defer { hadParticles = particles }
        return renderKey() != cachedKey || particles || hadParticles || cuts() != lastCuts
    }
    var downAt = CGPoint.zero, dragging = false
    var pendingPet: DispatchWorkItem?
    var lastDrag = CGPoint.zero, lastDragT = 0.0, dragV = CGPoint.zero

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        downAt = NSEvent.mouseLocation; dragging = false
        lastDrag = downAt; lastDragT = e.timestamp; dragV = .zero
        if e.clickCount >= 2 { pendingPet?.cancel(); pendingPet = nil; cat.nudge(from: downAt.x) }
    }

    var brushTravel: CGFloat = 0

    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        if cat.brushMode {   // brushing instead of picking up
            pendingPet?.cancel()
            brushTravel += hypot(m.x - lastDrag.x, m.y - lastDrag.y); lastDrag = m
            if brushTravel > 18 { brushTravel = 0; cat.brushStroke(at: m) }
            return
        }
        if !dragging && hypot(m.x - downAt.x, m.y - downAt.y) > 6 {
            if cat.isHidden { return }
            dragging = true; pendingPet?.cancel(); cat.startCarry()
        }
        guard dragging else { return }
        let dt = max(e.timestamp - lastDragT, 0.001)
        let v = P((m.x - lastDrag.x) / dt, (m.y - lastDrag.y) / dt)
        dragV = P(dragV.x * 0.5 + v.x * 0.5, dragV.y * 0.5 + v.y * 0.5)
        lastDrag = m; lastDragT = e.timestamp
        cat.carry(to: m)
    }

    override func mouseUp(with e: NSEvent) {
        if dragging { dragging = false; cat.drop(velocity: dragV); return }
        guard e.clickCount == 1 else { return }
        let w = DispatchWorkItem { [weak self] in self?.cat.pet() }
        pendingPet = w
        DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.3), execute: w)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let cat else { return }
        ctx.clear(bounds)
        let key = renderKey()
        if key != cachedKey {   // only re-render the sprite when the pose (or look) actually changed
            cachedImage = Painter.image(cat.pose, coat: coats[key.coat], facing: cat.facing, size: bounds.size, origin: P(OX, OY),
                                        collar: key.collar.map { rgb($0) }, sizeMul: CGFloat(key.size))
            cachedKey = key
        }
        lastCuts = cuts()
        if let img = cachedImage {
            ctx.interpolationQuality = .none
            ctx.draw(img, in: bounds)
        }
        if let o = window?.frame.origin {
            for f in cat.fur where !(f.age > 2.5 && Int(f.age * 12) % 2 == 0) {
                let c = coats[cat.s.coat % coats.count]
                ctx.setFillColor((Int(f.p.x) % 2 == 0 ? c.fur : c.light).cgColor)
                ctx.fill(CGRect(x: ((f.p.x - o.x) / PX).rounded() * PX, y: ((f.p.y - o.y) / PX).rounded() * PX, width: PX, height: PX))
            }
            let m = NSEvent.mouseLocation
            if cat.brushMode && bounds.contains(P(m.x - o.x, m.y - o.y)) {   // the brush follows the cursor
                let rows = [".oooooo.......", "owwwwwwooooooo", "owwwwwwhhhhhho", "oooooooooooooo", ".b.b.b........", ".b.b.b........"]
                let pal: [Character: NSColor] = ["o": rgb(0x2A1C12), "w": rgb(0xC98A4B), "h": rgb(0xA0662E), "b": rgb(0xEDE6D6)]
                let bx = ((m.x - o.x) / PX).rounded(), by = ((m.y - o.y) / PX).rounded()
                for (r, line) in rows.enumerated() {
                    for (c, ch) in line.enumerated() {
                        guard let col = pal[ch] else { continue }
                        ctx.setFillColor(col.cgColor)
                        ctx.fill(CGRect(x: (bx - 2 + CGFloat(c)) * PX, y: (by + CGFloat(rows.count - 1 - r)) * PX, width: PX, height: PX))
                    }
                }
            }
            for l in cat.litter where !(l.age > 2.1 && Int(l.age * 12) % 2 == 0) {
                ctx.setFillColor((Int(l.p.x) % 3 == 0 ? rgb(0xA89F88) : rgb(0xCFC7B0)).cgColor)
                ctx.fill(CGRect(x: ((l.p.x - o.x) / PX).rounded() * PX, y: ((l.p.y - o.y) / PX).rounded() * PX, width: PX, height: PX))
            }
            for h in cat.hearts where !(h.age > 1.1 && Int(h.age * 12) % 2 == 0) {   // blink out at the end
                CatView.drawHeart(ctx, at: P(h.p.x - o.x, h.p.y - o.y))
            }
            for r in cat.occluders() { ctx.clear(r.offsetBy(dx: -o.x, dy: -o.y)) }
        }
    }

    static let heartFill = ["##.##", "#####", ".###.", "..#.."]

    /// A little outlined pixel heart, centered on `at`.
    static func drawHeart(_ ctx: CGContext, at: CGPoint) {
        let rows = heartFill.count, cols = heartFill[0].count
        func filled(_ c: Int, _ r: Int) -> Bool {
            r >= 0 && r < rows && c >= 0 && c < cols && Array(heartFill[r])[c] == "#"
        }
        let ox = (at.x / PX).rounded() * PX - CGFloat(cols) * PX / 2, oy = (at.y / PX).rounded() * PX
        for r in -1...rows {
            for c in -1...cols {
                let col: NSColor
                if filled(c, r) { col = (r == 0 && c == 0) ? rgb(0xFFB3C9) : rgb(0xFF5C8A) }
                else if filled(c - 1, r) || filled(c + 1, r) || filled(c, r - 1) || filled(c, r + 1) { col = rgb(0x5A1A2E) }
                else { continue }
                ctx.setFillColor(col.cgColor)
                ctx.fill(CGRect(x: ox + CGFloat(c) * PX, y: oy + CGFloat(rows - 1 - r) * PX, width: PX, height: PX))
            }
        }
    }
}

/// Hand-placed pixel-art bowls. Each bowl is a character grid (top row first) mapped through a palette;
/// the kibble heap and water surface are painted into the grid according to how full the bowl is.
final class BowlView: NSView {
    var cat: Cat!
    var shownFood = 0.0, shownWater = 0.0
    var bits: [(p: CGPoint, vy: CGFloat, water: Bool)] = []   // in art pixels
    var time = 0.0

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    static let size = CGSize(width: 120, height: 60)
    static let foodCol = 2, waterCol = 22                       // left edge of each grid, in art pixels
    static let foodLX: CGFloat = 30, waterLX: CGFloat = 87      // bowl centers, in points

    static let palette: [Character: NSColor] = [
        "o": rgb(0x1A1A22),
        "P": rgb(0xF9C3D3), "p": rgb(0xEB8FAB), "d": rgb(0xC9688A), "i": rgb(0x8E3F58), "f": rgb(0xFFF4F7),
        "k": rgb(0x8B5A2B), "K": rgb(0xC08442),
        "B": rgb(0xBDEEF5), "b": rgb(0x6FC3D6), "e": rgb(0x4FA3BA), "j": rgb(0x2F6F80), "w": rgb(0xF4FDFF),
        "q": rgb(0x8FD8FF), "Q": rgb(0xFFFFFF),
    ]

    static let dish = [
        "...oooooooooo...",
        ".ooPPPPPPPPPPoo.",
        "oPPiiiiiiiiiiPPo",
        "oPPPPPPPPPPPPPPo",
        ".oppppppppppppo.",
        ".oppppppppppppo.",
        "..oddddddddddo..",
        "...oooooooooo...",
    ]
    static let fish = [".fff.f", "ffffff", ".fff.f"]

    static let bowl = [
        "...oooooooo...",
        ".ooBBBBBBBBoo.",
        "oBBjjjjjjjjBBo",
        "oBBBBBBBBBBBBo",
        "obbbbbbbbbbbbo",
        "obbbbbbbbbbbbo",
        ".obbbbbbbbbbo.",
        ".oeeeeeeeeeeo.",
        "..oeeeeeeeeo..",
        "...oooooooo...",
    ]
    static let drop = ["..w..", ".www.", "wwwww", ".www."]

    func bowlHit(_ p: CGPoint) -> Bool? {
        if abs(p.x - BowlView.foodLX) < 26 && p.y < 36 { return false }
        if abs(p.x - BowlView.waterLX) < 24 && p.y < 36 { return true }
        return nil
    }

    override func mouseDown(with e: NSEvent) {
        guard let water = bowlHit(convert(e.locationInWindow, from: nil)) else { return }
        fill(water: water)
    }

    func fill(water: Bool) {
        let cx = (water ? BowlView.waterLX : BowlView.foodLX) / PX
        for _ in 0..<(water ? 8 : 12) {
            bits.append((P((cx + rnd(-4, 4)).rounded(), rnd(15, 19)), rnd(-8, 0), water))
        }
        if water { cat.s.water = 1; cat.sound.play(cat.sound.bottle, 0.5) } else { cat.s.food = 1; cat.sound.play(cat.sound.pop, 0.5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.cat.heardBowl(water: water) }
    }

    func tick(_ dt: Double) {
        time += dt
        let k = min(1, dt * 3)
        shownFood += (cat.s.food - shownFood) * k
        shownWater += (cat.s.water - shownWater) * k
        bits = bits.compactMap { b in
            let vy = b.vy - 300 * CGFloat(dt)
            let p = b.p.off(0, vy * CGFloat(dt))
            return p.y < (b.water ? 9 : 10) ? nil : (p, vy, b.water)
        }
        let key = [Int(shownFood * 40), Int(shownWater * 40), shimmerStep(), bits.count]
        if key != lastKey || !bits.isEmpty { needsDisplay = true; lastKey = key }
    }

    var lastKey: [Int] = []
    func shimmerStep() -> Int { Int((sin(time * 1.4) + 1) * 2) }

    func foodGrid(_ lv: Double) -> [[Character]] {
        var g = Array(repeating: Array(repeating: Character("."), count: 16), count: 3) + BowlView.dish.map(Array.init)
        for (r, row) in BowlView.fish.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." { g[3 + 4 + r][5 + c] = ch }
        }
        func kib(_ r: Int, _ cols: ClosedRange<Int>) { for c in cols { g[r][c] = (r * 3 + c) % 4 == 0 ? "K" : "k" } }
        if lv > 0.04 { kib(5, 3...12) }
        if lv > 0.3 { kib(4, 3...12) }
        if lv > 0.55 { kib(3, 4...11) }
        if lv > 0.75 { kib(2, 5...10) }
        if lv > 0.92 { kib(1, 6...9) }
        // outline the heap where it pokes above the rim
        for r in 0..<4 {
            for c in 0..<16 where g[r][c] == "k" || g[r][c] == "K" {
                for (dr, dc) in [(-1, 0), (0, -1), (0, 1)] where r + dr >= 0 && g[r + dr][c + dc] == "." { g[r + dr][c + dc] = "o" }
            }
        }
        return g
    }

    func waterGrid(_ lv: Double) -> [[Character]] {
        var g = BowlView.bowl.map(Array.init)
        for (r, row) in BowlView.drop.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." { g[4 + r][5 + c] = ch }
        }
        if lv > 0.04 { for c in (lv < 0.5 ? 5...8 : 3...10) { g[2][c] = "q" } }
        if lv > 0.6 { for c in 4...9 { g[1][c] = "q" } }
        if lv > 0.3 {
            let s = 4 + shimmerStep()
            g[2][s] = "Q"; g[2][s + 1] = "Q"
        }
        return g
    }

    func paint(_ ctx: CGContext, _ g: [[Character]], col: Int, row: Int) {
        for (r, line) in g.enumerated() {
            for (c, ch) in line.enumerated() {
                guard let color = BowlView.palette[ch] else { continue }
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: CGFloat(col + c) * PX, y: CGFloat(row + g.count - 1 - r) * PX, width: PX, height: PX))
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext, cat != nil, let ctx = pixelContext(bounds.size) else { return }
        g.clear(bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
        ctx.fill(CGRect(x: CGFloat(BowlView.foodCol + 2) * PX, y: 0, width: 12 * PX, height: PX))
        ctx.fill(CGRect(x: CGFloat(BowlView.waterCol + 2) * PX, y: 0, width: 10 * PX, height: PX))
        paint(ctx, foodGrid(shownFood), col: BowlView.foodCol, row: 1)
        paint(ctx, waterGrid(shownWater), col: BowlView.waterCol, row: 1)
        for b in bits {
            ctx.setFillColor((b.water ? rgb(0x8FD8FF) : (Int(b.p.x) % 2 == 0 ? rgb(0x8B5A2B) : rgb(0xC08442))).cgColor)
            ctx.fill(CGRect(x: b.p.x.rounded() * PX, y: b.p.y.rounded() * PX, width: PX, height: PX))
        }
        if let img = ctx.makeImage() { g.interpolationQuality = .none; g.draw(img, in: bounds) }
    }
}
