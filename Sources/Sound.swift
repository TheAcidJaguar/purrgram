// DesktopCat — purrs, synthesized meows and other sounds.

import Cocoa

// MARK: - Sound

final class SoundBox {
    var enabled: () -> Bool = { true }
    let purr = NSSound(named: "Purr")
    let pop = NSSound(named: "Pop")
    let bottle = NSSound(named: "Bottle")
    let tink = NSSound(named: "Tink")
    var meows: [NSSound] = []

    init() {
        meows = [(720.0, 0.5), (820.0, 0.38), (650.0, 0.7), (900.0, 0.3)].compactMap { SoundBox.synthMeow(base: $0.0, dur: $0.1) }
    }

    func play(_ s: NSSound?, _ vol: Float) {
        guard enabled(), let s else { return }
        if s.isPlaying { s.stop() }
        s.volume = vol; s.play()
    }
    func meow() { play(meows.filter { !$0.isPlaying }.randomElement(), 0.35) }
    func jingle() { play(tink, 0.08) }
    func doPurr() { guard purr?.isPlaying != true else { return }; play(purr, 0.6) }

    /// A tiny synthesized "mew": pitch rises then falls while a formant sweeps m → e → ow.
    static func synthMeow(base: Double, dur: Double) -> NSSound? {
        let sr = 22050.0, n = Int(sr * dur)
        var samples = [Int16](repeating: 0, count: n)
        var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = base * (1 + 0.45 * sin(.pi * pow(t, 0.6))) * (1 - 0.22 * t) * (1 + 0.01 * sin(Double(i) / sr * 2 * .pi * 7))
            ph += f / sr
            let formant = 900 + 1500 * sin(.pi * pow(t, 0.8))
            var v = 0.0
            for k in 1...7 {
                let hk = Double(k) * f
                let a = exp(-pow((hk - formant) / 650, 2)) + 0.25 / Double(k)
                v += a * sin(2 * .pi * Double(k) * ph)
            }
            let env = pow(sin(.pi * t), 0.6) * min(1, t / 0.05)
            samples[i] = Int16(clampd(v * 0.2 * env, -1, 1) * 32000)
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let len = UInt32(n * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + len); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(len)
        for s in samples { u16(UInt16(bitPattern: s)) }
        return NSSound(data: d)
    }
}
