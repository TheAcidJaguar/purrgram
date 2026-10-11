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
/// The warm backdrop shared by the README / download page pictures: a peach gradient that matches the app icon,
/// and a soft "floor" band of height `floor` along the bottom of the screen.
func drawBackdrop(_ ctx: CGContext, width W: CGFloat, height H: CGFloat, floor: CGFloat) {
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0xFFF5EF).cgColor, rgb(0xFBDDD0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
    ctx.setFillColor(rgb(0xF2C7B6).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: floor))
    ctx.setFillColor(rgb(0xE8B3A0).cgColor); ctx.fill(CGRect(x: 0, y: floor - PX, width: W, height: PX))
}

/// An app window for the cat to sit on or scratch: rounded body with a soft shadow, title bar, traffic lights
/// and a few lines of "content".
func drawAppWindow(_ ctx: CGContext, _ win: CGRect) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.setFillColor(.white); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.clip()
    ctx.setFillColor(rgb(0xEDEBF0).cgColor); ctx.fill(CGRect(x: win.minX, y: win.maxY - 26, width: win.width, height: 26))
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(rgb(c).cgColor); ctx.fillEllipse(in: CGRect(x: win.minX + 12 + CGFloat(i) * 18, y: win.maxY - 18, width: 11, height: 11))
    }
    ctx.setFillColor(rgb(0xE9E6EE).cgColor)
    for (i, w) in [0.62, 0.8, 0.5].enumerated() where win.maxY - 56 - CGFloat(i) * 26 > win.minY + 12 {
        ctx.fill(CGRect(x: win.minX + 22, y: win.maxY - 56 - CGFloat(i) * 26, width: (win.width - 44) * CGFloat(w), height: 10))
    }
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setStrokeColor(rgb(0xD3CED9).cgColor); ctx.setLineWidth(1); ctx.strokePath()
}

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
    case "eat":   // eat at the food bowl, then go drink
        world.bowlRect = CGRect(x: 150, y: 0, width: BowlView.size.width, height: BowlView.size.height)
        cat.s.belly = 0.2; cat.s.hydration = 0.2; cat.s.food = 0.9; cat.s.water = 0.9
        cat.x = world.foodX - 33 * cat.cs; cat.act = .eat(false)
        cat.queue = [.walk(world.waterX - 33 * cat.cs, 90), .face(1), .eat(true), .sit(2)]
        seconds = 15
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
    let floorH: CGFloat = 18   // the floor band under the scene, as in the hero picture
    let W = Int(world.screen.width * scale), H = Int((world.screen.height + floorH) * scale)
    for f in 0..<frames {
        let t = Double(f) / fps
        let hidden = scene == "hide" && t > 1.8 && t < 3.6
        if !hidden { cat.tick(1 / fps); bv.tick(1 / fps) }
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.interpolationQuality = .none
        ctx.scaleBy(x: scale, y: scale)
        drawBackdrop(ctx, width: world.screen.width, height: world.screen.height + floorH, floor: floorH)
        ctx.translateBy(x: 0, y: floorH)   // the scene stands on the floor band
        if scene != "hide" && scene != "eat" { drawAppWindow(ctx, win.rect) }
        if !hidden {
            let eating: Bool = { if case .eat = cat.act { return true }; return false }()
            func bowls() {
                if let b = bowlsImage(bv) { ctx.draw(b, in: CGRect(origin: P(world.bowlRect.minX, 0), size: BowlView.size)) }
            }
            if scene == "hide" || scene == "eat" { bowls() }
            if let img = Painter.image(cat.pose, coat: coats[coat], facing: cat.facing, size: CGSize(width: VW, height: VH),
                                       origin: P(OX, OY), collar: rgb(0xC8323C)) {
                let at = CGRect(x: (cat.x - OX).rounded() + cat.shake, y: (cat.y - OY).rounded(), width: VW, height: VH)
                if scene == "eat" && eating, let layer = CGContext(data: nil, width: Int(VW * scale), height: Int(VH * scale), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    layer.interpolationQuality = .none; layer.scaleBy(x: scale, y: scale)
                    layer.draw(img, in: CGRect(x: 0, y: 0, width: VW, height: VH))
                    for r in BowlView.underBowls { layer.clear(r.offsetBy(dx: world.bowlRect.minX - at.minX, dy: -at.minY)) }
                    if let cut = layer.makeImage() { ctx.draw(cut, in: at) }
                } else {
                    ctx.draw(img, in: at)
                }
            }
            if scene == "eat" && eating, let front = bv.frontImage() {   // the face goes down inside the bowl
                ctx.draw(front, in: CGRect(origin: P(world.bowlRect.minX, 0), size: BowlView.size))
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
    guard let raw = Painter.image(p, coat: coats[0], facing: 1, size: CGSize(width: 120, height: 120), origin: P(60, 18)),
          let sprite = croppedToContent(raw) else { return }
    renderPNG(size: CGSize(width: 1024, height: 1024), scale: 1, to: path) { ctx in
        // Standard macOS icon grid: an 824pt rounded tile centered on the 1024 canvas, with a soft drop shadow.
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(shape); ctx.setFillColor(rgb(0xF5B19E).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()   // gentle top-to-bottom gradient
        ctx.addPath(shape); ctx.clip()
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0xFBD3C5).cgColor, rgb(0xF2A48F).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
        ctx.restoreGState()
        // The cat, scaled by a whole number so every art pixel stays a crisp square, centered in the tile.
        let k = floor(min(560 / CGFloat(sprite.height), 560 / CGFloat(sprite.width)))
        let w = CGFloat(sprite.width) * k, h = CGFloat(sprite.height) * k
        ctx.interpolationQuality = .none
        ctx.draw(sprite, in: CGRect(x: (512 - w / 2).rounded(), y: (512 - h / 2).rounded(), width: w, height: h))
    }
}

/// Trim the transparent margin around a sprite.
func croppedToContent(_ img: CGImage) -> CGImage? {
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let px = ctx.data?.bindMemory(to: UInt32.self, capacity: w * h) else { return nil }
    var x0 = w, y0 = h, x1 = -1, y1 = -1
    for y in 0..<h { for x in 0..<w where px[y * w + x] >> 24 != 0 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    guard x1 >= x0 else { return nil }
    return img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))   // memory rows run top-down, like cropping
}

/// The README's hero image: a little desktop scene drawn with the real sprites (`--hero out.png`).
func renderHero(_ path: String) {
    let W: CGFloat = 760, H: CGFloat = 232, floorY: CGFloat = 30
    let win = CGRect(x: 40, y: floorY, width: 236, height: 138)
    let world = World()
    world.screen = CGRect(x: 0, y: 0, width: W, height: H); world.vis = world.screen
    world.all = [Plat(id: 1, rect: win, order: 0)]; world.stand = world.all

    /// A cat in a given coat and moment, drawn with its feet at (x, y).
    func drawCat(_ ctx: CGContext, coat: String, act: Act, t: Double, x: CGFloat, y: CGFloat, facing: CGFloat,
                 onWindow: Bool = false, collar: Int? = 0xC8323C) {
        var st = SaveState(); st.coat = coats.firstIndex { $0.name == coat } ?? 0
        let cat = Cat(world: world, state: st, sound: SoundBox())
        cat.act = act; cat.actT = t; cat.time = t; cat.phase = 1.1; cat.facing = facing
        if onWindow { cat.surface = .window(1); cat.surfRect = win }
        let c = coats[st.coat]
        guard let img = Painter.image(cat.makePose(), coat: c, facing: facing, size: CGSize(width: VW, height: VH), origin: P(OX, OY),
                                      collar: collar.map { rgb($0) }) else { return }
        ctx.draw(img, in: CGRect(x: (x - OX).rounded(), y: (y - OY).rounded(), width: VW, height: VH))
    }

    renderPNG(size: CGSize(width: W, height: H), scale: 3, to: path) { ctx in
        drawBackdrop(ctx, width: W, height: H, floor: floorY)
        drawAppWindow(ctx, win)

        // The cast.
        drawCat(ctx, coat: "Siamese", act: .loaf(99), t: 1, x: 190, y: win.maxY, facing: -1, onWindow: true)
        drawCat(ctx, coat: "Orange Tabby", act: .walk(9e9, 70), t: 0.3, x: 336, y: floorY, facing: 1)
        drawCat(ctx, coat: "Tuxedo", act: .bat, t: 0.12, x: 452, y: floorY, facing: 1, collar: 0x2F6FD6)
        if let yarn = pixelContext(ToyView.size) {
            ToyView.paint(yarn, spin: 1, trail: -1, moving: false, grounded: true)
            if let im = yarn.makeImage() {
                ctx.draw(im, in: CGRect(x: 516 - ToyView.size.width / 2, y: floorY - PX, width: ToyView.size.width, height: ToyView.size.height))
            }
        }
        let bowlX: CGFloat = 626
        let cat = Cat(world: world, state: SaveState(), sound: SoundBox())
        let bv = BowlView(frame: NSRect(origin: .zero, size: BowlView.size))
        bv.cat = cat; bv.shownFood = 0.8; bv.shownWater = 0.9
        if let bowls = bowlsImage(bv) {
            ctx.draw(bowls, in: CGRect(x: bowlX, y: floorY - PX, width: BowlView.size.width, height: BowlView.size.height))
        }
        drawCat(ctx, coat: "Slate", act: .sit(99), t: 0.2, x: bowlX - 22, y: floorY, facing: 1)   // waiting by the bowls
    }
}

/// The bowls on a transparent layer of their own: BowlView clears its whole rectangle as it draws, which is
/// right for its window in the app but would punch a box out of anything it's drawn on top of.
func bowlsImage(_ bv: BowlView, scale: CGFloat = 3) -> CGImage? {
    let size = BowlView.size
    guard let c = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    c.interpolationQuality = .none; c.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    bv.draw(bv.bounds)
    NSGraphicsContext.restoreGraphicsState()
    return c.makeImage()
}
