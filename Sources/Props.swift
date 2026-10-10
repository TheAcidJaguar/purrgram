// DesktopCat — the yarn ball, treats, hairballs and the mouse.

import Cocoa

// MARK: - Props: yarn ball, treat, mouse

/// Draw a pixel sprite (rows top-first, chars mapped through `palette`, "." empty) with an optional
/// one-pixel outline. (col, row) is the art-pixel position of the grid's bottom-left; `flip` mirrors it.
func drawSprite(_ ctx: CGContext, _ rows: [String], _ palette: [Character: NSColor], col: Int, row: Int,
                flip: Bool = false, outline: NSColor? = nil) {
    let g = rows.map { Array($0) }, h = g.count, w = g.map(\.count).max() ?? 0
    func at(_ c: Int, _ r: Int) -> Character? {   // r counts up from the bottom
        guard r >= 0, r < h else { return nil }
        let line = g[h - 1 - r], cc = flip ? w - 1 - c : c
        guard cc >= 0, cc < line.count, line[cc] != "." else { return nil }
        return line[cc]
    }
    for r in -1...h {
        for c in -1...w {
            let color: NSColor
            if let ch = at(c, r), let pc = palette[ch] { color = pc }
            else if let o = outline, at(c - 1, r) != nil || at(c + 1, r) != nil || at(c, r - 1) != nil || at(c, r + 1) != nil { color = o }
            else { continue }
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: CGFloat(col + c) * PX, y: CGFloat(row + r) * PX, width: PX, height: PX))
        }
    }
}

enum ToyKind { case yarn, treat, hairball }

/// A small physical prop (yarn ball or treat): falls, bounces, rolls with friction, lands on window tops,
/// rides along when they move and tumbles off their edges. Yarn that rolls off the screen is gone.
final class Toy {
    let world: World
    let kind: ToyKind
    var x: CGFloat, y: CGFloat          // bottom center, in screen points
    var vx: CGFloat = 0, vy: CGFloat = 0
    var surface: Surface = .air
    var surfRect = CGRect.zero
    var spin: CGFloat = 0
    var trail: CGFloat = -1             // which side the loose strand trails on
    var held = false                    // dragged by the user or hugged by the cat
    var gone = false
    var age = 0.0

    init(world: World, kind: ToyKind, x: CGFloat, y: CGFloat) { self.world = world; self.kind = kind; self.x = x; self.y = y }

    func kick(_ kvx: CGFloat, _ kvy: CGFloat) {
        vx = kvx; vy = kvy
        if kvy > 0 { surface = .air }
    }

    func tick(_ dt: Double) {
        age += dt
        if kind == .hairball && age > 4 { gone = true }   // hairballs clean themselves up after a few seconds
        guard !held, !gone else { return }
        let d = CGFloat(dt), v = world.vis
        if case .window(let id) = surface {
            if let p = world.plat(id), world.stand.contains(where: { $0.id == id }) {
                if p.rect != surfRect { x += p.rect.minX - surfRect.minX; y = p.top; surfRect = p.rect }
                if x < p.rect.minX || x > p.rect.maxX { surface = .air }
            } else { surface = .air }
        }
        if surface == .air {
            let py = y
            vy -= gravity * d; x += vx * d; y += vy * d
            if vy <= 0 {
                var best: Plat? = nil
                for p in world.stand where py >= p.top - 1 && y <= p.top && x > p.rect.minX + 4 && x < p.rect.maxX - 4 && world.topVisible(p, x) {
                    if best == nil || p.top > best!.top { best = p }
                }
                if let p = best { land(p.top, .window(p.id), p.rect) }
                else if y <= world.floorY { land(world.floorY, .floor, .zero) }
            }
        } else {
            x += vx * d
            vx *= CGFloat(exp((kind == .yarn ? -1.6 : -6) * dt))
            if abs(vx) < 6 { vx = 0 }
        }
        if kind == .yarn {
            if x < v.minX - 24 || x > v.maxX + 24 { gone = true }   // knocked clean off the screen
        } else {
            if x < v.minX + 12 { x = v.minX + 12; vx = abs(vx) * 0.5 }
            if x > v.maxX - 12 { x = v.maxX - 12; vx = -abs(vx) * 0.5 }
        }
        if y > v.maxY - 30 { y = v.maxY - 30; vy = min(vy, 0) }
        spin += vx * d / 9
        if abs(vx) > 5 { trail = vx > 0 ? -1 : 1 }
    }

    func land(_ top: CGFloat, _ s: Surface, _ r: CGRect) {
        y = top
        if vy < -260 { vy = -vy * (kind == .treat ? 0.25 : 0.4); vx *= 0.85 }   // bounce
        else { vy = 0; surface = s; surfRect = r }
    }
}

final class ToyView: NSView {
    var toy: Toy!
    var cat: Cat!
    var downAt = CGPoint.zero, dragging = false
    var lastDrag = CGPoint.zero, lastDragT = 0.0, dragV = CGPoint.zero

    static let size = CGSize(width: 90, height: 36)
    static let ballCol = 12                       // left column of the 7-wide ball
    static let ball = ["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."]
    static let body = rgb(0xE0506C), shade = rgb(0xA8293F), hi = rgb(0xF7A3B5), ink = rgb(0x2A1418)

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func hitRect() -> CGRect { CGRect(x: toy.x - 15, y: toy.y - 2, width: 30, height: 30) }

    var lastSig: [CGFloat] = []
    /// Ask for a redraw only if the toy's appearance changed (rolling, landing) — moving the window is free.
    func refresh() {
        let sig: [CGFloat] = [floor(toy.spin), toy.trail, toy.surface == .air ? 1 : 0, abs(toy.vx) > 5 ? 1 : 0]
        if sig != lastSig { lastSig = sig; needsDisplay = true }
    }

    override func mouseDown(with e: NSEvent) {
        if toy.kind == .hairball { toy.gone = true; return }   // click to clean it up
        downAt = NSEvent.mouseLocation; dragging = false
        lastDrag = downAt; lastDragT = e.timestamp; dragV = .zero
    }

    override func mouseDragged(with e: NSEvent) {
        guard toy.kind == .yarn else { return }
        let m = NSEvent.mouseLocation
        if !dragging && hypot(m.x - downAt.x, m.y - downAt.y) > 4 { dragging = true; toy.held = true; toy.surface = .air }
        guard dragging else { return }
        let dt = max(e.timestamp - lastDragT, 0.001)
        let v = P((m.x - lastDrag.x) / dt, (m.y - lastDrag.y) / dt)
        dragV = P(dragV.x * 0.5 + v.x * 0.5, dragV.y * 0.5 + v.y * 0.5)
        lastDrag = m; lastDragT = e.timestamp
        toy.x = m.x; toy.y = m.y - 13
    }

    override func mouseUp(with e: NSEvent) {
        guard toy.kind == .yarn else { return }
        if dragging {
            dragging = false; toy.held = false; toy.surface = .air
            toy.vx = clampf(dragV.x * 0.6, -1200, 1200); toy.vy = clampf(dragV.y * 0.6, -400, 1200)
        } else {
            toy.kick((toy.x >= downAt.x ? 1 : -1) * rnd(260, 360), rnd(200, 300))   // flick it away from the cursor
        }
        cat.toyNoticed()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext, toy != nil, let ctx = pixelContext(bounds.size) else { return }
        g.clear(bounds)
        if toy.kind == .treat { ToyView.paintTreat(ctx, grounded: toy.surface != .air) }
        else if toy.kind == .hairball { ToyView.paintHairball(ctx) }
        else { ToyView.paint(ctx, spin: toy.spin, trail: toy.trail, moving: abs(toy.vx) > 5, grounded: toy.surface != .air) }
        if let img = ctx.makeImage() { g.interpolationQuality = .none; g.draw(img, in: bounds) }
    }

    /// Ball rows 2…8 (outline 1…9) centered on column 15; shadow on row 0; the loose strand lies along the ground.
    static func paint(_ ctx: CGContext, spin: CGFloat, trail: CGFloat, moving: Bool, grounded: Bool) {
        func px(_ c: Int, _ r: Int, _ col: NSColor) {
            ctx.setFillColor(col.cgColor); ctx.fill(CGRect(x: CGFloat(c) * PX, y: CGFloat(r) * PX, width: PX, height: PX))
        }
        if grounded {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
            ctx.fill(CGRect(x: CGFloat(ballCol + 1) * PX, y: 0, width: 5 * PX, height: PX))
        }
        let t = Int(trail), start = 15 + t * 3
        for i in 1...7 {
            let wob = moving ? (i + Int(spin * 2)) % 4 == 0 : i % 4 == 2
            px(start + t * i, wob ? 2 : 1, shade)
        }
        let rows = ball.count
        func filled(_ c: Int, _ r: Int) -> Bool { r >= 0 && r < rows && c >= 0 && c < 7 && Array(ball[r])[c] == "#" }
        let frame = ((Int(floor(spin)) % 3) + 3) % 3
        for r in -1...rows {
            for c in -1...7 {
                let row = 2 + (rows - 1 - r), col = ballCol + c
                if filled(c, r) {
                    var color = (c + r + frame) % 3 == 0 ? shade : body       // wound strands that roll as it moves
                    if (r == 1 && c == 2) || (r == 2 && c == 1) { color = hi }
                    px(col, row, color)
                } else if filled(c - 1, r) || filled(c + 1, r) || filled(c, r - 1) || filled(c, r + 1) {
                    px(col, row, ink)
                }
            }
        }
    }

    /// A small, slightly glossy lump. Gross. Click to clean.
    static func paintHairball(_ ctx: CGContext) {
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        ctx.fill(CGRect(x: 13 * PX, y: 0, width: 5 * PX, height: PX))
        drawSprite(ctx, [".hhH.", "hhdhh", "dhhdh"], ["h": rgb(0x7D6A4E), "H": rgb(0xB9A784), "d": rgb(0x5A4A34)],
                   col: 13, row: 2, outline: rgb(0x2A2016))
    }

    /// A little fish-shaped treat.
    static func paintTreat(_ ctx: CGContext, grounded: Bool) {
        if grounded {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
            ctx.fill(CGRect(x: 13 * PX, y: 0, width: 5 * PX, height: PX))
        }
        drawSprite(ctx, [".hoo.t", "oeooot", ".ooo.t"],
                   ["o": rgb(0xF2994A), "h": rgb(0xFFC98F), "e": rgb(0x2A1A10), "t": rgb(0xD9772E)],
                   col: 12, row: 2, outline: rgb(0x3A2010))
    }
}

/// A little mouse that scurries in from an edge, sniffs about, and bolts off the screen when the cat gets close.
final class Critter {
    enum Mode { case scurry, pause, flee }
    let world: World
    var x: CGFloat, y: CGFloat
    var dir: CGFloat
    var mode = Mode.scurry, modeT = 0.0, modeDur = rndD(1.5, 3)
    var speed: CGFloat = 110, phase: CGFloat = 0, age = 0.0
    var gone = false

    init(world: World, fromLeft: Bool) {
        self.world = world
        dir = fromLeft ? 1 : -1
        x = fromLeft ? world.vis.minX - 14 : world.vis.maxX + 14
        y = world.floorY
    }

    var fleeing: Bool { mode == .flee }

    func tick(_ dt: Double, cat: Cat) {
        guard !gone else { return }
        age += dt; modeT += dt
        let v = world.vis
        y = world.floorY
        let catDist = abs(cat.x - x), catLow = cat.y < world.floorY + 60
        if mode != .flee && ((catDist < 170 && catLow && !cat.isSleeping) || (cat.isAirborne && catDist < 320)) {
            mode = .flee; dir = x >= cat.x ? 1 : -1; speed = 340
        }
        switch mode {
        case .flee: break
        case .scurry:
            if modeT > modeDur { mode = .pause; modeT = 0; modeDur = rndD(0.5, 1.6); speed = 0 }
        case .pause:
            if modeT > modeDur {
                mode = .scurry; modeT = 0; modeDur = rndD(0.8, 2.2); speed = rnd(80, 130)
                if age > 40 { dir = x < v.midX ? -1 : 1; modeDur = 99 }        // bored: head for the nearest edge
                else if x < v.minX + 120 { dir = 1 } else if x > v.maxX - 120 { dir = -1 } else if chance(0.35) { dir = -dir }
            }
        }
        x += dir * speed * CGFloat(dt)
        phase += speed * CGFloat(dt) / 5
        if (x < v.minX - 30 && dir < 0) || (x > v.maxX + 30 && dir > 0) { gone = true }
    }
}

final class CritterView: NSView {
    var critter: Critter!
    static let size = CGSize(width: 60, height: 30)
    static let palette: [Character: NSColor] = ["g": rgb(0x9C9CAA), "w": rgb(0xC9C9D4), "p": rgb(0xEBA4B4), "e": rgb(0x111111),
                                                "n": rgb(0xFF8FA3), "f": rgb(0x6A6A78)]
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext, let m = critter, let ctx = pixelContext(bounds.size) else { return }
        g.clear(bounds)
        let moving = m.speed > 0, step = Int(m.phase) % 2 == 0
        let sniff = !moving && Int(m.age * 6) % 2 == 0
        let rows = [
            ".....gp..",
            "..gggggg.",
            ".gggggge" + (sniff ? "." : "n"),
            "gwwwwggg" + (sniff ? "n" : "."),
            moving ? (step ? ".f..f...." : "..f..f...") : ".f...f...",
        ]
        let flip = m.dir < 0, cols = 20
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        ctx.fill(CGRect(x: 7 * PX, y: 0, width: 7 * PX, height: PX))
        // tail: a wiggly line trailing behind
        ctx.setFillColor(rgb(0xC27C8E).cgColor)
        for i in 0..<5 {
            let c = 5 - i, r = 3 + ((i + Int(m.phase)) % 3 == 0 ? 1 : 0)
            let cc = flip ? cols - 1 - c : c
            ctx.fill(CGRect(x: CGFloat(cc) * PX, y: CGFloat(r) * PX, width: PX, height: PX))
        }
        drawSprite(ctx, rows, CritterView.palette, col: flip ? cols - 6 - 9 : 6, row: 2, flip: flip, outline: rgb(0x26262E))
        if let img = ctx.makeImage() { g.interpolationQuality = .none; g.draw(img, in: bounds) }
    }
}
