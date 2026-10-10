// DesktopCat — small helpers, constants and pixel-drawing utilities.

import Cocoa

// MARK: - Helpers

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
extension CGPoint { func off(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) } }
func clampf(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
func clampd(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
func rnd(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }
func rndD(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }
func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let gravity: CGFloat = 1500
let maxJumpUp: CGFloat = 760
let PX: CGFloat = 3   // one art pixel = 3 screen points
// Cat view geometry (multiples of PX): the cat's feet sit at (OX, OY) inside a VW x VH transparent window.
let VW: CGFloat = 231, VH: CGFloat = 192, OX: CGFloat = 114, OY: CGFloat = 36

func pixelContext(_ size: CGSize) -> CGContext? {
    guard let ctx = CGContext(data: nil, width: Int(size.width / PX), height: Int(size.height / PX), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setShouldAntialias(false); ctx.setAllowsAntialiasing(false)
    ctx.interpolationQuality = .none
    ctx.scaleBy(x: 1 / PX, y: 1 / PX)
    return ctx
}

/// Draw a little bitmap given as rows of "#" (top row first).
func sprite(_ ctx: CGContext, _ rows: [String], _ at: CGPoint, _ col: NSColor) {
    ctx.setFillColor(col.cgColor)
    let ox = (at.x / PX).rounded() * PX, oy = (at.y / PX).rounded() * PX
    for (r, line) in rows.enumerated() {
        for (i, ch) in line.enumerated() where ch == "#" {
            ctx.fill(CGRect(x: ox + CGFloat(i) * PX, y: oy + CGFloat(rows.count - 1 - r) * PX, width: PX, height: PX))
        }
    }
}
