// DesktopCat — exports every animation as PNG frame strips for the Windows Lite build, which just plays them back.

import Cocoa

/// One animation to pre-render: the action, how long the loop is, its frame rate, and whether the clock that drives
/// tail sways / breathing advances (some poses look best with it frozen).
private struct Clip {
    let name: String, act: Act, seconds: Double, fps: Double
    var loop = true, clock = true
    var speed: CGFloat = 0        // walking speed in points/s (drives the leg phase)
    var vy: CGFloat = 0           // vertical speed for the in-the-air pose
    var blinkAt: Double? = nil    // one blink during the loop
}

private let clips: [Clip] = [
    Clip(name: "sit", act: .sit(9e9), seconds: 2 * .pi / 1.7, fps: 10, blinkAt: 1.0),
    Clip(name: "lookUp", act: .lookUp(9e9), seconds: 2 * .pi / 3, fps: 10),
    Clip(name: "loaf", act: .loaf(9e9), seconds: 3, fps: 10, blinkAt: 1.5),
    Clip(name: "sleep", act: .sleep(9e9), seconds: 2 * .pi / 1.9, fps: 8),
    Clip(name: "groom", act: .groom(9e9), seconds: 7, fps: 12),
    Clip(name: "scratch", act: .scratch(9e9), seconds: 2 * .pi / 3, fps: 20),
    Clip(name: "stretch", act: .stretch, seconds: 2.6, fps: 15, loop: false),
    Clip(name: "archStretch", act: .archStretch, seconds: 2.4, fps: 15, loop: false),
    Clip(name: "bigArch", act: .bigArch, seconds: 3.2, fps: 15, loop: false),
    Clip(name: "legStretch", act: .legStretch, seconds: 2.0, fps: 15, loop: false),
    Clip(name: "yawn", act: .yawn, seconds: 1.6, fps: 15, loop: false),
    Clip(name: "petted", act: .petted(9e9), seconds: 2 * .pi / 5 * 4, fps: 15),
    Clip(name: "annoyed", act: .annoyed(9e9), seconds: 2 * .pi / 3, fps: 15),
    Clip(name: "swat", act: .swat, seconds: 0.6, fps: 20, loop: false),
    Clip(name: "crouch", act: .crouch(9e9), seconds: 2 * .pi * 3 / 14, fps: 15, clock: false),
    Clip(name: "walk", act: .walk(9e9, 74.8), seconds: 2 * .pi / 2.2, fps: 20, speed: 74.8),
    Clip(name: "run", act: .walk(9e9, 299.2), seconds: 2 * .pi / 2.2, fps: 30, speed: 299.2),
    Clip(name: "carried", act: .carried, seconds: 2 * .pi / 3, fps: 10),
    Clip(name: "airUp", act: .hop(0, 0), seconds: 0.1, fps: 10, vy: 400),
    Clip(name: "airDown", act: .hop(0, 0), seconds: 0.1, fps: 10, vy: -400),
    Clip(name: "land", act: .land, seconds: 0.22, fps: 30, loop: false),
    Clip(name: "eatFood", act: .eat(false), seconds: 2 * .pi / 1.3, fps: 12),
    Clip(name: "eatWater", act: .eat(true), seconds: 2 * .pi / 1.3, fps: 15),
    Clip(name: "waitBowl", act: .waitBowl(false), seconds: 4, fps: 12),
]

private func writePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Lay frames side by side in one strip.
private func strip(_ frames: [CGImage]) -> CGImage? {
    guard let f = frames.first,
          let ctx = CGContext(data: nil, width: f.width * frames.count, height: f.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    for (i, im) in frames.enumerated() { ctx.draw(im, in: CGRect(x: i * f.width, y: 0, width: f.width, height: f.height)) }
    return ctx.makeImage()
}

/// `--export-frames <dir>`: cats/<coat>/<clip>_R.png and _L.png (frame strips, art-pixel resolution),
/// bowls/*.png and manifest.json.
func exportFrames(_ dir: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir + "/bowls", withIntermediateDirectories: true)
    var st = SaveState(); st.sound = false; st.happiness = 0.8
    let cat = Cat(world: World(), state: st, sound: SoundBox())
    let size = CGSize(width: VW, height: VH)
    var manifest: [String: Any] = [:]
    var clipInfo: [[String: Any]] = []
    for c in clips {
        clipInfo.append(["name": c.name, "fps": c.fps, "frames": max(1, Int((c.seconds * c.fps).rounded())), "loop": c.loop])
    }
    for (ci, coat) in coats.enumerated() {
        let cdir = "\(dir)/cats/\(ci)"
        try? fm.createDirectory(atPath: cdir, withIntermediateDirectories: true)
        cat.s.coat = ci
        for c in clips {
            let n = max(1, Int((c.seconds * c.fps).rounded()))
            for facing: CGFloat in [1, -1] {
                var frames: [CGImage] = []
                for f in 0..<n {
                    let t = Double(f) / c.fps
                    cat.act = c.act; cat.actT = t; cat.time = c.clock ? t : 0
                    cat.phase = c.speed * CGFloat(t) / 8.5
                    cat.vx = 0; cat.vy = c.vy
                    cat.lastMeowAt = -99; cat.startleUntil = -99; cat.tiltUntil = -99
                    cat.blinkUntil = c.blinkAt.map { t >= $0 && t < $0 + 0.14 ? t + 1 : -1 } ?? -1
                    cat.surface = .floor
                    guard let img = Painter.image(cat.makePose(), coat: coat, facing: facing, size: size, origin: P(OX, OY),
                                                  collar: rgb(0xC8323C)) else { continue }
                    frames.append(img)
                }
                if let s = strip(frames) { writePNG(s, "\(cdir)/\(c.name)_\(facing > 0 ? "R" : "L").png") }
            }
        }
    }

    // Bowls: every look each bowl can have, as full-size bowl-view images (so offsets match), plus front walls.
    let bv = BowlView(frame: NSRect(origin: .zero, size: BowlView.size))
    bv.cat = cat
    let foodLevels = [0.0, 0.1, 0.4, 0.6, 0.8, 1.0], waterLevels = [0.0, 0.2, 0.4, 0.55, 0.8]
    func bowlImage(shadow: Bool, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = pixelContext(BowlView.size) else { return nil }
        if shadow {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
            ctx.fill(CGRect(x: CGFloat(BowlView.foodCol + 2) * PX, y: 0, width: 12 * PX, height: PX))
            ctx.fill(CGRect(x: CGFloat(BowlView.waterCol + 2) * PX, y: 0, width: 10 * PX, height: PX))
        }
        draw(ctx)
        return ctx.makeImage()
    }
    cat.act = .sit(1)
    for (i, lv) in foodLevels.enumerated() {
        if let im = bowlImage(shadow: true, { bv.paint($0, bv.foodGrid(lv), col: BowlView.foodCol, row: 1) }) { writePNG(im, "\(dir)/bowls/food\(i).png") }
        if let im = bowlImage(shadow: false, { bv.paint($0, bv.foodGrid(lv), col: BowlView.foodCol, row: 1, fromRow: BowlView.foodFrontRow) }) {
            writePNG(im, "\(dir)/bowls/food\(i)_front.png")
        }
    }
    // Shimmer steps 0…4 while idle; ripple rings 0…2 while drinking.
    for (i, lv) in waterLevels.enumerated() {
        for k in 0...4 {
            cat.act = .sit(1)
            bv.time = asin(min(1, Double(k) / 2 - 1 + 0.001)) / 1.4
            if k == 4 { bv.time = .pi / 2 / 1.4 }
            if let im = bowlImage(shadow: true, { bv.paint($0, bv.waterGrid(lv), col: BowlView.waterCol, row: 1) }) { writePNG(im, "\(dir)/bowls/water\(i)_s\(k).png") }
        }
        for r in 0...2 {
            cat.act = .eat(true)
            bv.time = (Double(r) + 0.5) * .pi / 13
            if let im = bowlImage(shadow: true, { bv.paint($0, bv.waterGrid(lv), col: BowlView.waterCol, row: 1) }) { writePNG(im, "\(dir)/bowls/water\(i)_d\(r).png") }
            if let im = bowlImage(shadow: false, { bv.paint($0, bv.waterGrid(lv), col: BowlView.waterCol, row: 1, fromRow: BowlView.waterFrontRow) }) {
                writePNG(im, "\(dir)/bowls/water\(i)_d\(r)_front.png")
            }
        }
    }

    manifest["px"] = Double(PX)
    manifest["frameW"] = Int(VW / PX); manifest["frameH"] = Int(VH / PX)
    manifest["originX"] = Int(OX / PX); manifest["originY"] = Int(OY / PX)
    manifest["bowlW"] = Int(BowlView.size.width / PX); manifest["bowlH"] = Int(BowlView.size.height / PX)
    manifest["foodLX"] = Double(BowlView.foodLX); manifest["waterLX"] = Double(BowlView.waterLX)
    manifest["foodLevels"] = foodLevels; manifest["waterLevels"] = waterLevels
    manifest["underBowls"] = BowlView.underBowls.map { [Int($0.minX / PX), Int($0.minY / PX), Int($0.width / PX), Int($0.height / PX)] }
    manifest["coats"] = coats.map { ["name": $0.name, "size": Double($0.size), "fluff": $0.fluff] }
    manifest["clips"] = clipInfo
    manifest["catScale"] = Double(catScale)
    if let d = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
        try? d.write(to: URL(fileURLWithPath: dir + "/manifest.json"))
    }
    print("✓ exported \(coats.count) coats × \(clips.count) clips × 2 facings to \(dir)")
}
