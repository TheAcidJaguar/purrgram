// DesktopCat — offline renders: sprite sheets, close-ups, GIF demos and the app icon.

import Cocoa

// MARK: - Offline rendering (sprite sheet for previews, app icon)

func renderPNG(size: CGSize, scale: CGFloat, to path: String, _ body: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    g.cgContext.scaleBy(x: scale, y: scale)
    g.cgContext.interpolationQuality = .none
    body(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func renderSheet(_ path: String) {
    let world = World()
    let cat = Cat(world: world, state: SaveState(), sound: SoundBox())
    let shots: [(String, Act, Double, CGFloat, CGFloat)] = [
        ("sit", .sit(9), 0.2, 0, 0), ("walk", .walk(9e9, 70), 0.3, 0, 0), ("run", .walk(9e9, 300), 0.4, 0, 0),
        ("crouch/wiggle", .crouch(3), 0.35, 0, 0), ("leap up", .leap(.zero), 0, 300, 600), ("falling", .hop(0, 0), 0, 200, -400),
        ("loaf", .loaf(9), 1, 0, 0), ("sleep", .sleep(99), 1, 0, 0), ("groom: lick", .groom(9), 0.3, 0, 0),
        ("groom: ear", .groom(9), 4.6, 0, 0), ("scratch", .scratch(9), 0.4, 0, 0), ("front stretch", .stretch, 1.3, 0, 0),
        ("arch stretch", .archStretch, 1.2, 0, 0), ("leg stretch", .legStretch, 1.0, 0, 0), ("yawn", .yawn, 0.7, 0, 0),
        ("crawl under", .crawl(9e9, 1), 0.3, 0, 0), ("eat", .eat(false), 0.2, 0, 0), ("drink", .eat(true), 0.1, 0, 0),
        ("petted", .petted(9), 0.5, 0, 0), ("annoyed", .annoyed(9), 0.5, 0, 0), ("swat", .swat, 0.1, 0, 0),
        ("carried", .carried, 0, 0, 0), ("look up", .lookUp(9), 0.1, 0, 0), ("paw at bowl", .waitBowl(false), 0.3, 0, 0),
        ("land", .land, 0.05, 0, 0),
    ]
    let cols = 5, cw: CGFloat = 231, ch: CGFloat = 150
    let rows = (shots.count + cols - 1) / cols + 2
    let W = CGFloat(cols) * cw, H = CGFloat(rows) * ch
    renderPNG(size: CGSize(width: W, height: H), scale: 2, to: path) { ctx in
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        for (i, s) in shots.enumerated() {
            let col = i % cols, row = rows - 1 - i / cols
            cat.act = s.1; cat.actT = s.2; cat.time = s.2; cat.phase = 1.1; cat.vx = s.3; cat.vy = s.4
            cat.lastMeowAt = -9
            if let img = Painter.image(cat.makePose(), coat: coats[0], facing: 1, size: CGSize(width: VW, height: VH), origin: P(OX, OY)) {
                ctx.draw(img, in: CGRect(x: CGFloat(col) * cw, y: CGFloat(row) * ch - 4, width: VW, height: VH))
            }
            if s.0 == "petted" { CatView.drawHeart(ctx, at: P(CGFloat(col) * cw + OX + 14, CGFloat(row) * ch + 78)) }
            NSAttributedString(string: s.0, attributes: [.font: NSFont.systemFont(ofSize: 11)]).draw(at: P(CGFloat(col) * cw + 6, CGFloat(row) * ch + 4))
        }
        cat.act = .sit(9); cat.time = 0.2
        let p = cat.makePose()
        for (i, c) in coats.enumerated() {
            if let img = Painter.image(p, coat: c, facing: 1, size: CGSize(width: VW, height: VH), origin: P(OX, OY)) {
                ctx.draw(img, in: CGRect(x: CGFloat(i) * (W / CGFloat(coats.count)) - 60, y: ch - 4, width: VW, height: VH))
            }
        }
        let bv = BowlView(frame: NSRect(origin: .zero, size: BowlView.size))
        bv.cat = cat; bv.shownFood = 0.8; bv.shownWater = 0.8
        ctx.saveGState(); ctx.translateBy(x: 20, y: 10); bv.draw(bv.bounds); ctx.restoreGState()
        bv.shownFood = 0; bv.shownWater = 0
        ctx.saveGState(); ctx.translateBy(x: 180, y: 10); bv.draw(bv.bounds); ctx.restoreGState()
    }
}

/// Close-up of the bowls at a few fill levels plus a few cats, for checking pixel details.
func renderCloseup(_ path: String, coat: Int = 0) {
    let cat = Cat(world: World(), state: SaveState(), sound: SoundBox())
    let bv = BowlView(frame: NSRect(origin: .zero, size: BowlView.size))
    bv.cat = cat
    renderPNG(size: CGSize(width: 480, height: 400), scale: 4, to: path) { ctx in
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 480, height: 400).fill()
        for (i, lv) in [1.0, 0.6, 0.0].enumerated() {
            bv.shownFood = lv; bv.shownWater = lv; bv.time = Double(i)
            ctx.saveGState(); ctx.translateBy(x: CGFloat(i) * 150 + 10, y: 10); bv.draw(bv.bounds); ctx.restoreGState()
        }
        for (i, sp) in ([0, 0.4, 0.8] as [CGFloat]).enumerated() {
            if let tc = pixelContext(ToyView.size) {
                if i == 2 { ToyView.paintHairball(tc) } else { ToyView.paint(tc, spin: sp * 3, trail: -1, moving: i > 0, grounded: true) }
                if let im = tc.makeImage() { ctx.draw(im, in: CGRect(x: 360 + CGFloat(i) * 40, y: 150, width: ToyView.size.width, height: ToyView.size.height)) }
            }
        }
        let acts: [Act] = [.bigArch, .bigArch, .bigArch, .bigArch, .bigArch, .bigArch, .bigArch, .bigArch]
        for (i, a) in acts.enumerated() {
            cat.act = a; cat.actT = [0.0, 0.35, 0.7, 1.0, 1.5, 2.7, 2.9, 3.2][i]; cat.time = 0.3; cat.phase = 1.1
            cat.s.coat = coat
            if let img = Painter.image(cat.makePose(), coat: coats[coat], facing: 1, size: CGSize(width: VW, height: VH), origin: P(OX, OY), collar: rgb(0xC8323C)) {
                ctx.draw(img, in: CGRect(x: CGFloat(i % 4) * 115 - 60, y: i < 4 ? 220 : 70, width: VW, height: VH))
            }
        }
    }
}

/// Animated GIF demos rendered with the real drawing code: "catch" (edge catch), "claw" (scratching a window
/// edge) and "hide" (the Hide Everything toggle).
func renderGIF(_ scene: String, _ path: String, coat: Int) {
    let world = World()
    world.screen = CGRect(x: 0, y: 0, width: 330, height: 260); world.vis = world.screen
    world.bowlRect = CGRect(x: 200, y: 0, width: BowlView.size.width, height: BowlView.size.height)
    let win = scene == "catch" ? Plat(id: 1, rect: CGRect(x: 125, y: 40, width: 185, height: 140), order: 0)
                               : Plat(id: 1, rect: CGRect(x: 175, y: 12, width: 150, height: 200), order: 0)
    world.all = [win]; world.stand = scene == "catch" ? [win] : []
    var st = SaveState(); st.coat = coat; st.sound = false
    let cat = Cat(world: world, state: st, sound: SoundBox())
    cat.x = 70; cat.y = 0; cat.facing = 1
    var seconds = 6.2
    switch scene {
    case "catch":
        cat.act = .crouch(0.9); cat.forceCatch = true; cat.forceGrip = true
        cat.queue = [.leapOn(1, 55), .sit(1.6)]
    case "claw":
        cat.x = 40; cat.act = .sit(0.6)
        cat.queue = [.walk(175 - 39 * cat.cs, 80), .face(1), .claw(1, 175, 4.5), .legStretch, .sit(2)]
        seconds = 9.5
    default:   // hide
        cat.x = 90; cat.act = .walk(150, 60); cat.queue = [.sit(9)]
        seconds = 5.5
    }
    let bv = BowlView(frame: NSRect(origin: .zero, size: BowlView.size))
    bv.cat = cat; bv.shownFood = 0.8; bv.shownWater = 0.8
    let scale: CGFloat = 2, fps = 24.0
    let frames = Int(seconds * fps)
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "com.compuserve.gif" as CFString, frames, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
    let W = Int(world.screen.width * scale), H = Int(world.screen.height * scale)
    for f in 0..<frames {
        let t = Double(f) / fps
        let hidden = scene == "hide" && t > 1.8 && t < 3.6
        if !hidden { cat.tick(1 / fps) }
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(rgb(0xE9E4F2).cgColor); ctx.fill(world.screen)
        if scene != "hide" {   // a simple app window: body + title bar with traffic lights
            let r = win.rect
            ctx.setFillColor(rgb(0xFFFFFF).cgColor); ctx.fill(r)
            ctx.setFillColor(rgb(0xDADADF).cgColor); ctx.fill(CGRect(x: r.minX, y: r.maxY - 22, width: r.width, height: 22))
            for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                ctx.setFillColor(rgb(c).cgColor); ctx.fillEllipse(in: CGRect(x: r.minX + 9 + CGFloat(i) * 15, y: r.maxY - 15, width: 9, height: 9))
            }
            ctx.setStrokeColor(rgb(0xB8B8C0).cgColor); ctx.setLineWidth(1); ctx.stroke(r)
        }
        if !hidden {
            if scene == "hide" {
                ctx.saveGState(); ctx.translateBy(x: world.bowlRect.minX, y: 0)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                bv.draw(bv.bounds)
                NSGraphicsContext.restoreGraphicsState(); ctx.restoreGState()
            }
            if let img = Painter.image(cat.pose, coat: coats[coat], facing: cat.facing, size: CGSize(width: VW, height: VH),
                                       origin: P(OX, OY), collar: rgb(0xC8323C)) {
                ctx.draw(img, in: CGRect(x: (cat.x - OX).rounded() + cat.shake, y: (cat.y - OY).rounded(), width: VW, height: VH))
            }
        }
        if scene == "hide" {   // a little caption so the toggle reads in the clip
            let label = hidden ? "Hide Everything  ⌘H" : (t > 3.6 ? "Unhide  ⌘H" : "")
            if !label.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                               .foregroundColor: rgb(0x55506A)]).draw(at: P(12, 230))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if let frame = ctx.makeImage() {
            CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]] as CFDictionary)
        }
    }
    CGImageDestinationFinalize(dest)
}

func renderIcon(_ path: String) {
    let cat = Cat(world: World(), state: SaveState(), sound: SoundBox())
    cat.act = .sit(9); cat.time = 0
    var p = cat.makePose(); p.eyes = .happy; p.shadow = false
    renderPNG(size: CGSize(width: 1024, height: 1024), scale: 1, to: path) { ctx in
        let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        rgb(0xF7B9A8).setFill(); bg.fill()
        if let img = Painter.image(p, coat: coats[0], facing: 1, size: CGSize(width: 120, height: 120), origin: P(60, 18)) {
            ctx.draw(img, in: CGRect(x: 512 - 360, y: 140, width: 720, height: 720))
        }
    }
}
