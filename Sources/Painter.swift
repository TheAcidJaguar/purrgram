// DesktopCat — poses and the pixel-art renderer.

import Cocoa

// MARK: - Pose + pixel painter

enum Eyes { case open, wide, half, closed, happy, annoyed, strain }
enum Mouth { case none, meow, tongue, chew }

struct Limb: Equatable {
    var hip: CGPoint
    var foot: CGPoint
    var knee: CGPoint? = nil
    var far = false
    var w: CGFloat = 7.5
}

/// Everything is in cat-local points: feet on y = 0, facing +x.
struct Pose: Equatable {
    var bodyC = P(0, 22), bodyW: CGFloat = 54, bodyH: CGFloat = 24, bodyRot: CGFloat = 0
    var haunchC: CGPoint? = nil, haunchR: CGFloat = 14
    var headC = P(29, 40), headR: CGFloat = 14, headTilt: CGFloat = 0
    var earFlat: CGFloat = 0
    var eyes: Eyes = .open
    var mouth: Mouth = .none
    var legs: [Limb] = []
    var tail: [CGPoint] = []
    var tailW: CGFloat = 6.4
    var tailFront = false
    var frontLimb: Limb? = nil   // drawn over the face, e.g. a paw washing it
    var shadow = true
    var rot: CGFloat = 0
}

extension Limb {
    func mix(_ o: Limb, _ k: CGFloat) -> Limb {
        func m(_ a: CGPoint, _ b: CGPoint) -> CGPoint { P(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k) }
        let mid = P((hip.x + foot.x) / 2, (hip.y + foot.y) / 2), omid = P((o.hip.x + o.foot.x) / 2, (o.hip.y + o.foot.y) / 2)
        return Limb(hip: m(hip, o.hip), foot: m(foot, o.foot), knee: m(knee ?? mid, o.knee ?? omid), far: far, w: w + (o.w - w) * k)
    }
    func shifted(_ dy: CGFloat) -> Limb {
        Limb(hip: hip.off(0, dy), foot: foot.off(0, dy), knee: knee?.off(0, dy), far: far, w: w)
    }
}

extension Pose {
    /// Blend two poses (same number of legs and tail points); discrete details come from whichever is nearer.
    func mix(_ o: Pose, _ k: CGFloat) -> Pose {
        func m(_ a: CGPoint, _ b: CGPoint) -> CGPoint { P(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k) }
        func f(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }
        var p = k < 0.5 ? self : o
        p.bodyC = m(bodyC, o.bodyC); p.bodyW = f(bodyW, o.bodyW); p.bodyH = f(bodyH, o.bodyH); p.bodyRot = f(bodyRot, o.bodyRot)
        p.headC = m(headC, o.headC); p.headR = f(headR, o.headR); p.headTilt = f(headTilt, o.headTilt); p.earFlat = f(earFlat, o.earFlat)
        if legs.count == o.legs.count { p.legs = zip(legs, o.legs).map { $0.mix($1, k) } }
        if tail.count == o.tail.count { p.tail = zip(tail, o.tail).map { m($0, $1) } }
        p.tailW = f(tailW, o.tailW)
        return p
    }
    /// The same pose moved up (or down) by `dy`.
    func shifted(_ dy: CGFloat) -> Pose {
        var p = self
        p.bodyC = bodyC.off(0, dy); p.headC = headC.off(0, dy); p.haunchC = haunchC?.off(0, dy)
        p.legs = legs.map { $0.shifted(dy) }; p.frontLimb = frontLimb?.shifted(dy)
        p.tail = tail.map { $0.off(0, dy) }
        return p
    }
}

let catScale: CGFloat = 0.85   // poses are authored at 1.0; the cat is drawn a little smaller

/// A view onto a bitmap context's pixels (rows run top to bottom in memory).
struct Buf {
    let p: UnsafeMutablePointer<UInt32>
    let w: Int, h: Int, stride: Int
    init?(_ c: CGContext) {
        guard let d = c.data else { return nil }
        stride = c.bytesPerRow / 4; w = c.width; h = c.height
        p = d.bindMemory(to: UInt32.self, capacity: stride * h)
    }
    func get(_ x: Int, _ y: Int) -> UInt32 { (x < 0 || y < 0 || x >= w || y >= h) ? 0 : p[y * stride + x] }
    func set(_ x: Int, _ y: Int, _ v: UInt32) { p[y * stride + x] = v }
    func on(_ x: Int, _ y: Int) -> Bool { get(x, y) >> 24 != 0 }
    func n4(_ x: Int, _ y: Int) -> [UInt32] { [get(x - 1, y), get(x + 1, y), get(x, y - 1), get(x, y + 1)].filter { $0 >> 24 != 0 } }
    /// How many of the four neighbors are filled (no allocation — this runs for every pixel, every render).
    @inline(__always) func count4(_ x: Int, _ y: Int) -> Int {
        (on(x - 1, y) ? 1 : 0) + (on(x + 1, y) ? 1 : 0) + (on(x, y - 1) ? 1 : 0) + (on(x, y + 1) ? 1 : 0)
    }
}

func pack(_ c: NSColor) -> UInt32 {
    let s = c.usingColorSpace(.sRGB) ?? c
    let r = UInt32((s.redComponent * 255).rounded()), g = UInt32((s.greenComponent * 255).rounded()), b = UInt32((s.blueComponent * 255).rounded())
    return 0xFF00_0000 | (b << 16) | (g << 8) | r
}

func similar(_ a: UInt32, _ b: UInt32) -> Bool {
    for sh in [0, 8, 16] as [UInt32] where abs(Int((a >> sh) & 0xff) - Int((b >> sh) & 0xff)) > 4 { return false }
    return true
}

func majority(_ ns: [UInt32]) -> UInt32 {
    ns.max { a, b in ns.filter { similar($0, a) }.count < ns.filter { similar($0, b) }.count }!
}

/// Draws poses as clean pixel art. Each layer (far legs, main body, front tail) is filled flat with
/// antialiasing off, tidied (stray pixels, notches and specks removed), shaded along its bottom edge,
/// then stamped onto the sprite with an exact one-pixel outline. Faces are placed pixel by pixel.
struct Painter {
    let c: Coat
    var collar: NSColor? = nil
    var limbCol: NSColor { c.points ? c.dark : c.fur }

    func scaled(_ p: Pose, _ k: CGFloat) -> Pose {
        func s(_ v: CGPoint) -> CGPoint { P(v.x * k, v.y * k) }
        var q = p
        q.bodyC = s(p.bodyC); q.bodyW *= k; q.bodyH *= k * c.bodyMul
        q.haunchC = p.haunchC.map(s); q.haunchR *= k * (c.bodyMul > 1 ? 1.06 : 1)
        q.headC = s(p.headC); q.headR *= k
        q.legs = p.legs.map { l in Limb(hip: s(l.hip), foot: s(l.foot), knee: l.knee.map(s), far: l.far, w: PX * 2) }
        q.frontLimb = p.frontLimb.map { l in Limb(hip: s(l.hip), foot: s(l.foot), knee: l.knee.map(s), far: false, w: PX * 2) }
        q.tail = p.tail.map(s)
        q.tailW = max(PX, (p.tailW > 7 ? PX * 3 : PX * 2) * c.tailMul)
        return q
    }

    static func image(_ pose: Pose, coat: Coat, facing: CGFloat, size: CGSize, origin: CGPoint, collar: NSColor? = nil,
                      sizeMul: CGFloat = 1) -> CGImage? {
        let pt = Painter(c: coat, collar: collar)
        let k = catScale * coat.size * sizeMul
        let p = pt.scaled(pose, k)
        func layer(_ draw: (CGContext) -> Void) -> (CGContext, Buf)? {
            guard let ctx = pixelContext(size) else { return nil }
            ctx.translateBy(x: origin.x, y: origin.y); ctx.scaleBy(x: facing, y: 1)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            if p.rot != 0 { let pv = 22 * k; ctx.translateBy(x: 0, y: pv); ctx.rotate(by: p.rot); ctx.translateBy(x: 0, y: -pv) }
            draw(ctx)
            guard let b = Buf(ctx) else { return nil }
            return (ctx, b)
        }
        guard let far = layer({ ctx in for l in p.legs where l.far { pt.limb(ctx, l) } }),
              let main = layer({ ctx in pt.mainFill(ctx, p) }),
              let front = layer({ ctx in
                  if p.tailFront { pt.tail(ctx, p) }
                  if let l = p.frontLimb { pt.limb(ctx, l) }
              }),
              let out = pixelContext(size), let ob = Buf(out) else { return nil }
        for b in [far.1, main.1, front.1] { tidy(b) }
        if coat.fluff { fluff(main.1); fluff(front.1) }
        fillHoles(main.1, pack(coat.fur.blended(withFraction: 0.3, of: .black)!))
        pt.shade(main.1); pt.shade(front.1)
        pt.details(main.0, p)
        if p.shadow {
            out.saveGState(); out.translateBy(x: origin.x, y: origin.y)
            out.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
            out.fillEllipse(in: CGRect(x: -27 * k, y: -PX, width: 56 * k, height: PX * 2))
            out.restoreGState()
        }
        let ol = pack(coat.outline)
        stamp(ob, far.1, ol); stamp(ob, main.1, ol); stamp(ob, front.1, ol)
        if coat.fluff {   // lynx tufts on the ear tips
            out.saveGState(); out.translateBy(x: origin.x, y: origin.y); out.scaleBy(x: facing, y: 1)
            out.setFillColor(coat.outline.cgColor)
            for (_, _, tip) in pt.ears(p) {
                let tx = (tip.x / PX).rounded() * PX - PX / 2, ty = (tip.y / PX).rounded() * PX
                out.fill(CGRect(x: tx, y: ty, width: PX, height: PX * 2))
            }
            out.restoreGState()
        }
        return out.makeImage()
    }

    /// Smooth the raw raster: drop orphan pixels and sideways spurs, fill one-pixel notches, despeckle colors.
    static func tidy(_ b: Buf) {
        var ch: [(Int, Int, UInt32)] = []
        ch.reserveCapacity(64)
        for y in 0..<b.h {
            for x in 0..<b.w {
                let n = b.count4(x, y)
                if b.on(x, y) {
                    let vert = b.on(x, y - 1) || b.on(x, y + 1)
                    if n == 0 || (n == 1 && !vert) { ch.append((x, y, 0)) }
                } else if n >= 3 {
                    ch.append((x, y, majority(b.n4(x, y))))
                }
            }
        }
        for (x, y, v) in ch { b.set(x, y, v) }
        ch.removeAll(keepingCapacity: true)
        for y in 0..<b.h {
            for x in 0..<b.w where b.on(x, y) && b.count4(x, y) == 4 {
                let v = b.get(x, y)
                if similar(b.get(x - 1, y), v) || similar(b.get(x + 1, y), v) || similar(b.get(x, y - 1), v) || similar(b.get(x, y + 1), v) { continue }
                let ns = b.n4(x, y)
                if !ns.contains(where: { similar($0, v) }) {
                    let m = majority(ns)
                    if ns.filter({ similar($0, m) }).count >= 3 { ch.append((x, y, m)) }
                }
            }
        }
        for (x, y, v) in ch { b.set(x, y, v) }
    }

    /// Empty pockets fully enclosed by fur (e.g. between gathered legs) become a soft shadow, not a black blob.
    static func fillHoles(_ b: Buf, _ color: UInt32) {
        var outside = [Bool](repeating: false, count: b.w * b.h)
        var stack: [(Int, Int)] = []
        for x in 0..<b.w { stack += [(x, 0), (x, b.h - 1)] }
        for y in 0..<b.h { stack += [(0, y), (b.w - 1, y)] }
        while let (x, y) = stack.popLast() {
            guard x >= 0, y >= 0, x < b.w, y < b.h, !outside[y * b.w + x], !b.on(x, y) else { continue }
            outside[y * b.w + x] = true
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
        }
        for y in 0..<b.h { for x in 0..<b.w where !b.on(x, y) && !outside[y * b.w + x] { b.set(x, y, color) } }
    }

    /// Shaggy fur: little tufts sticking out along top and side edges.
    static func fluff(_ b: Buf) {
        var ch: [(Int, Int, UInt32)] = []
        for y in 1..<b.h {
            for x in 1..<(b.w - 1) where b.on(x, y) {
                if !b.on(x, y - 1) && (x * 7 + y * 3) % 4 == 0 { ch.append((x, y - 1, b.get(x, y))) }
                if !b.on(x - 1, y) && (y * 5 + x) % 3 == 0 { ch.append((x - 1, y, b.get(x, y))) }
                if !b.on(x + 1, y) && (y * 5 + x) % 3 == 1 { ch.append((x + 1, y, b.get(x, y))) }
            }
        }
        for (x, y, v) in ch { b.set(x, y, v) }
    }

    /// Stamp a layer onto the sprite with a crisp four-connected outline.
    static func stamp(_ dst: Buf, _ src: Buf, _ outline: UInt32) {
        for y in 0..<src.h {
            for x in 0..<src.w {
                if src.on(x, y) { dst.set(x, y, src.get(x, y)) }
                else if src.count4(x, y) > 0 { dst.set(x, y, outline) }
            }
        }
    }

    /// One row of darker fur along every bottom edge gives the flat shapes a little weight.
    func shade(_ b: Buf) {
        let fur = pack(c.fur), lc = pack(limbCol)
        let dk = pack(c.fur.blended(withFraction: 0.18, of: .black)!), ldk = pack(limbCol.blended(withFraction: 0.18, of: .black)!)
        var ch: [(Int, Int, UInt32)] = []
        for y in 0..<b.h {
            for x in 0..<b.w where b.on(x, y) && !b.on(x, y + 1) {
                let v = b.get(x, y)
                if similar(v, fur) { ch.append((x, y, dk)) } else if similar(v, lc) { ch.append((x, y, ldk)) }
            }
        }
        for (x, y, v) in ch { b.set(x, y, v) }
    }

    func ellipse(_ ctr: CGPoint, _ w: CGFloat, _ h: CGFloat, _ rot: CGFloat = 0) -> CGPath {
        let p = CGMutablePath()
        p.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                     transform: CGAffineTransform(translationX: ctr.x, y: ctr.y).rotated(by: rot))
        return p
    }

    func fill(_ ctx: CGContext, _ path: CGPath, _ col: NSColor) {
        ctx.addPath(path); ctx.setFillColor(col.cgColor); ctx.fillPath()
    }

    func stroke(_ ctx: CGContext, _ path: CGPath, _ col: NSColor, _ w: CGFloat) {
        ctx.addPath(path); ctx.setStrokeColor(col.cgColor); ctx.setLineWidth(w); ctx.strokePath()
    }

    func mainFill(_ ctx: CGContext, _ p: Pose) {
        if !p.tailFront { tail(ctx, p) }
        body(ctx, p)
        if let hc = p.haunchC { haunch(ctx, hc, p.haunchR) }
        for l in p.legs where !l.far { limb(ctx, l) }
        headShape(ctx, p)
    }

    func limb(_ ctx: CGContext, _ l: Limb) {
        let path = CGMutablePath()
        path.move(to: l.hip)
        if let k = l.knee { path.addLine(to: k) }
        path.addLine(to: l.foot)
        var col = limbCol
        if l.far { col = col.blended(withFraction: 0.25, of: .black) ?? col }
        if c.points {   // colorpoint: cream at the top of the leg, seal-brown socks below the knee
            var upper = c.fur.blended(withFraction: 0.1, of: c.dark)!
            if l.far { upper = upper.blended(withFraction: 0.18, of: .black)! }
            stroke(ctx, path, upper, l.w)
            let k = l.knee ?? P(l.hip.x + (l.foot.x - l.hip.x) * 0.45, l.hip.y + (l.foot.y - l.hip.y) * 0.45)
            let sock = CGMutablePath(); sock.move(to: k); sock.addLine(to: l.foot)
            stroke(ctx, sock, col, l.w)
        } else {
            stroke(ctx, path, col, l.w)
        }
        var paw = c.whitePaws ? c.light : col
        if l.far && c.whitePaws { paw = paw.blended(withFraction: 0.15, of: .black) ?? paw }
        fill(ctx, ellipse(l.foot.off(1.5, 0.5), l.w * 1.5, l.w), paw)
    }

    func tail(_ ctx: CGContext, _ p: Pose) {
        guard p.tail.count == 4 else { return }
        let path = CGMutablePath()
        path.move(to: p.tail[0])
        path.addCurve(to: p.tail[3], control1: p.tail[1], control2: p.tail[2])
        stroke(ctx, path, c.points ? c.dark : c.fur, p.tailW)
        if c.stripes || c.spots {
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [PX, PX * 2])
            stroke(ctx, path, c.dark, p.tailW)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setLineCap(.round)
        }
    }

    func body(_ ctx: CGContext, _ p: Pose) {
        let path = ellipse(p.bodyC, p.bodyW, p.bodyH, p.bodyRot)
        fill(ctx, path, c.fur)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.translateBy(x: p.bodyC.x, y: p.bodyC.y); ctx.rotate(by: p.bodyRot)
        let w = p.bodyW, h = p.bodyH
        if !c.points {
            ctx.setFillColor(c.light.cgColor)
            ctx.fillEllipse(in: CGRect(x: -w * 0.3, y: -h * 0.95, width: w * 0.8, height: h * 0.72))
        }
        if c.chest { ctx.fillEllipse(in: CGRect(x: w * 0.12, y: -h * 0.75, width: w * 0.5, height: h * 1.15)) }
        if c.points {
            ctx.setFillColor(c.fur.blended(withFraction: 0.16, of: c.dark)!.cgColor)
            ctx.fillEllipse(in: CGRect(x: -w * 0.5, y: h * 0.12, width: w * 0.85, height: h * 0.75))
        }
        if c.stripes {
            ctx.setFillColor(c.dark.cgColor)
            for i in 0..<3 {
                let sx = -w * 0.28 + CGFloat(i) * w * 0.2
                ctx.fill(CGRect(x: sx, y: h * 0.15, width: PX, height: h * 0.45))
            }
        }
        if c.spots {   // rosettes: dark rings with a warm center
            for (i, j) in [(0, 0), (1, 1), (2, 0), (3, 1), (0, 2), (2, 2), (4, 0), (1, -1), (3, -1)] {
                let sx = -w * 0.38 + CGFloat(i) * w * 0.17, sy = -h * 0.2 + CGFloat(j) * h * 0.22
                ctx.setFillColor(c.dark.cgColor); ctx.fill(CGRect(x: sx, y: sy, width: PX * 2, height: PX * 2))
                ctx.setFillColor(c.fur.blended(withFraction: 0.35, of: c.dark)!.cgColor); ctx.fill(CGRect(x: sx + PX, y: sy, width: PX, height: PX))
            }
        }
        ctx.restoreGState()
    }

    func haunch(_ ctx: CGContext, _ hc: CGPoint, _ r: CGFloat) {
        let path = ellipse(hc, r * 2, r * 2)
        fill(ctx, path, c.points ? c.fur.blended(withFraction: 0.16, of: c.dark)! : c.fur)
        if c.spots {
            ctx.setFillColor(c.dark.cgColor)
            for (dx, dy) in [(-0.4, 0.3), (0.2, 0.5), (-0.1, -0.2)] as [(CGFloat, CGFloat)] {
                ctx.fill(CGRect(x: hc.x + dx * r, y: hc.y + dy * r, width: PX * 2, height: PX * 2))
            }
        }
        if c.stripes {
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.setFillColor(c.dark.cgColor)
            ctx.fill(CGRect(x: hc.x - r * 0.4, y: hc.y + r * 0.15, width: PX, height: r))
            ctx.restoreGState()
        }
    }

    /// Head center (snapped to the pixel grid) and radius. Tilts become nudges — rotating pixel art looks mushy.
    /// The head is drawn a touch oversized for that chibi pixel-kitten look.
    func headGeom(_ p: Pose) -> (CGPoint, CGFloat) {
        let r = p.headR * 1.35 * c.headMul
        let h = p.headC.off(p.headTilt * r * 0.5, -abs(p.headTilt) * r * 0.2)
        return (P((h.x / PX).rounded() * PX, (h.y / PX).rounded() * PX), r)
    }

    func ears(_ p: Pose) -> [(CGPoint, CGPoint, CGPoint)] {
        let (hc, r) = headGeom(p)
        let f = p.earFlat
        if c.wedge {   // big bat ears set low and wide, flaring out to the sides
            return [-1.0, 1.0].map { (s: CGFloat) in
                (hc.off(s * r * 1.08, r * 0.1), hc.off(s * r * 0.05 + PX * 0.5, r * 0.8),
                 hc.off(s * (r * 1.45 + f * r * 0.45) + PX * 0.5, r * (0.3 + 1.0 * c.earMul) - f * r * 0.7))
            }
        }
        return [-1.0, 1.0].map { (s: CGFloat) in
            (hc.off(s * r * 0.92, r * 0.3), hc.off(s * r * (c.earMul > 1.2 ? 0.05 : 0.12) + PX * 0.5, r * 0.8),
             hc.off(s * (r * (0.74 + (c.earMul - 1) * 0.25) + f * r * 0.5) + PX * 0.5, r * (0.3 + 1.0 * c.earMul) - f * r * 0.55))
        }
    }

    func headShape(_ ctx: CGContext, _ p: Pose) {
        let (hc, r) = headGeom(p)
        for (a, b, tip) in ears(p) {
            let ear = CGMutablePath(); ear.move(to: a); ear.addLine(to: tip); ear.addLine(to: b); ear.closeSubpath()
            fill(ctx, ear, c.points ? c.dark : c.fur)
        }
        fill(ctx, headPath(hc, r), c.fur)
    }

    /// The head's outline: an oval for most cats; for a wedge head (Sphynx), wide prominent cheekbones
    /// narrowing to a small chin and muzzle. `inset` shrinks it (used to keep face markings inside the outline).
    func headPath(_ hc: CGPoint, _ r: CGFloat, inset: CGFloat = 0) -> CGPath {
        guard c.wedge else { return ellipse(hc, r * 2.2 - inset * 2, r * 1.8 - inset * 2) }
        let k = (r - inset) / r
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { hc.off(x * r * k, y * r * k) }
        let path = CGMutablePath()
        path.move(to: q(0, 0.86))
        path.addQuadCurve(to: q(1.12, 0.3), control: q(1.02, 0.86))       // broad, flat-ish skull
        path.addQuadCurve(to: q(0.28, -0.98), control: q(1.18, -0.3))     // high cheekbone, then the jaw cuts in to a V
        path.addQuadCurve(to: q(-0.28, -0.98), control: q(0, -1.06))      // small, narrow chin
        path.addQuadCurve(to: q(-1.12, 0.3), control: q(-1.18, -0.3))
        path.addQuadCurve(to: q(0, 0.86), control: q(-1.02, 0.86))
        path.closeSubpath()
        return path
    }

    /// Inner ears, markings and the face — drawn after tidying so single pixels survive.
    func details(_ ctx: CGContext, _ p: Pose) {
        let (hc, r) = headGeom(p)
        for (a, b, tip) in ears(p) {
            let cx = (a.x + b.x + tip.x) / 3, cy = (a.y + b.y + tip.y) / 3
            func sh(_ q: CGPoint) -> CGPoint { P(cx + (q.x - cx) * 0.45, cy + (q.y - cy) * 0.45) }
            let inner = CGMutablePath(); inner.move(to: sh(a)); inner.addLine(to: sh(tip)); inner.addLine(to: sh(b)); inner.closeSubpath()
            fill(ctx, inner, c.inner)
            ctx.setFillColor(c.inner.cgColor)
            ctx.fill(CGRect(x: (cx / PX).rounded() * PX - PX / 2, y: (cy / PX).rounded() * PX - PX / 2, width: PX, height: PX))
        }
        func px(_ col: Int, _ row: Int, _ w: Int = 1, _ h: Int = 1, _ color: NSColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: hc.x + CGFloat(col) * PX, y: hc.y + CGFloat(row) * PX, width: CGFloat(w) * PX, height: CGFloat(h) * PX))
        }
        ctx.saveGState()
        ctx.addPath(headPath(hc, r, inset: PX / 2)); ctx.clip()
        if c.points {
            let soft = c.fur.blended(withFraction: 0.5, of: c.dark)!
            for (row, lo, hi) in [(1, 0, 1), (0, -1, 2), (-1, -2, 3), (-2, -2, 3), (-3, -2, 3), (-4, -1, 2)] {
                px(lo, row, hi - lo + 1, 1, soft)
            }
            for (row, lo, hi) in [(0, 0, 1), (-1, -1, 2), (-2, -1, 2), (-3, -1, 2), (-4, 0, 1)] {
                px(lo, row, hi - lo + 1, 1, c.dark)
            }
        }
        if c.chest {
            ctx.setFillColor(c.light.cgColor)
            ctx.fillEllipse(in: CGRect(x: hc.x - 2.5 * PX, y: hc.y - 6 * PX, width: 7 * PX, height: 5 * PX))
        }
        if c.stripes { for col in [-1, 1, 3] { px(col, 3, 1, 1, c.dark) } }
        if c.spots { px(-2, 3, 1, 1, c.dark); px(1, 4, 1, 1, c.dark); px(3, 3, 1, 1, c.dark); px(-3, -1, 1, 1, c.dark); px(4, -1, 1, 1, c.dark) }
        if c.wrinkles { px(-1, 3, 4, 1, c.dark); px(0, 4, 2, 1, c.dark) }
        if c.wedge {   // cheekbones angling down to a narrow muzzle: the wedge reads even where the chin meets the chest
            for (col, row) in [(-4, -1), (-3, -2), (-2, -3), (5, -1), (4, -2), (3, -3)] { px(col, row, 1, 1, c.dark) }
        }
        ctx.restoreGState()

        let ink = c.eye
        let lid = c.points ? c.dark : ink   // closed / happy eyes are drawn as dark lines
        // Open eyes are two-tone, green on top and yellow below, like real green-gold cat eyes. Siamese keep their blue.
        let top = c.points ? ink : rgb(0x4E9A26), low = c.points ? ink : rgb(0xD39A16)
        for (s, cx) in [(-1, -2), (1, 3)] {
            switch p.eyes {
            case .open where c.wedge:   // big lemon-shaped eyes, slanting up toward the ears
                px(cx, 1, 1, 1, top); px(cx, 0, 1, 1, low); px(cx + s, 1, 1, 1, top)
            case .open: px(cx, 1, 1, 1, top); px(cx, 0, 1, 1, low)
            case .wide: px(s < 0 ? cx - 1 : cx, 1, 2, 1, top); px(s < 0 ? cx - 1 : cx, 0, 2, 1, low)
            case .half: px(cx, 0, 1, 1, low)
            case .closed: px(s < 0 ? cx - 1 : cx, 0, 2, 1, lid)
            case .happy: px(cx - 1, 0, 1, 1, lid); px(cx, 1, 1, 1, lid); px(cx + 1, 0, 1, 1, lid)
            case .annoyed: px(s < 0 ? cx - 1 : cx, 1, 2, 1, lid); px(cx, 0, 1, 1, low)
            case .strain:   // squeezed shut: > <
                let o = s < 0 ? -1 : 1
                px(cx - o, 1, 1, 1, lid); px(cx, 0, 1, 1, lid); px(cx - o, -1, 1, 1, lid)
            }
        }
        px(0, -2, 2, 1, c.nose)
        switch p.mouth {
        case .meow: px(0, -4, 2, 2, rgb(0x5A1A22)); px(0, -4, 2, 1, rgb(0xE77A8C))
        case .tongue: px(0, -3, 2, 1, rgb(0xE77A8C))
        case .chew: px(0, -3, 2, 1, rgb(0x5A1A22))
        case .none: break
        }
        if let col = collar {   // collar band under the chin with a little gold bell
            let row = Int(floor(-r * (c.wedge ? 1.08 : 0.9) / PX))   // a wedge head's chin is narrow: the collar sits below it, on the neck
            let dk = col.blended(withFraction: 0.35, of: .black)!
            let (lo, w) = c.wedge ? (-2, 6) : (-3, 8)   // a slimmer collar on a slim neck
            px(lo, row, w, 1, col); px(lo, row, 1, 1, dk); px(lo + w - 1, row, 1, 1, dk)
            px(0, row - 2, 2, 2, rgb(0xE8B931)); px(0, row - 1, 1, 1, rgb(0xFFF0A8)); px(1, row - 2, 1, 1, rgb(0x9C7414))
        }
    }
}
