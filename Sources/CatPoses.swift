// DesktopCat — every pose the cat can strike.

import Cocoa

extension Cat {
    // MARK: poses

    func makePose() -> Pose {
        var p: Pose
        switch act {
        case .sit, .face, .goTo, .meow: p = sitPose()
        case .waitBowl: p = waitBowlPose(actT)
        case .lookUp: p = lookUpPose()
        case .loaf: p = loafPose()
        case .sleep, .hide: p = sleepPose()
        case .groom: p = groomPose(actT)
        case .scratch: p = scratchPose(actT)
        case .stretch: p = stretchPose(actT)
        case .archStretch: p = archPose(actT)
        case .bigArch: p = bigArchPose(actT)
        case .legStretch: p = legStretchPose(actT)
        case .yawn: p = yawnPose(actT)
        case .annoyed:
            p = sitPose(); p.eyes = .annoyed; p.earFlat = 0.7
            p.tail[3] = p.tail[3].off(0, CGFloat(sin(time * 9)) * 7 + 4)   // lashing tail
        case .swat:
            p = sitPose(); p.eyes = .annoyed; p.earFlat = 0.9
            p.legs[1] = Limb(hip: P(6, 30), foot: P(24 + CGFloat(sin(actT * 25)) * 4, 28), knee: P(16, 30))
        case .petted:   // nuzzle: lean in and bump the head against the hand
            p = sitPose(); p.eyes = .happy; p.earFlat = 0.2
            let n = CGFloat(sin(actT * 5)), lean = CGFloat(min(1, actT * 3))
            p.bodyRot = 1.2 - 0.12 * lean
            p.headC = p.headC.off((3 + 2.5 * n) * lean, (1.5 + 1.5 * abs(n)) * lean)
            p.headTilt = 0.3 * n
            p.tail = tailUp(P(-20, 14)); p.tailFront = false
        case .walk(_, let sp):
            p = standPose(phase: phase, amp: 1, run: sp > 200)
            if s.happiness < 0.3 { p.tail = [P(-25, 25), P(-34, 18), P(-40, 10), P(-44, 4)] }   // droopy
        case .crawl: p = crawlPose(actT)
        case .crouch: p = crouchPose(actT)
        case .leap, .hop, .leapOn: p = airPose()
        case .land: p = standPose(phase: 0, amp: 0, crouch: 0.7 * CGFloat(max(0, 1 - actT / 0.22)))
        case .eat(let w): p = eatPose(actT, w)
        case .carried: p = carriedPose()
        case .play: p = sitPose()
        case .chase: p = standPose(phase: phase, amp: 1, run: true); p.eyes = .wide
        case .pounceToy: p = airPose()
        case .bat: p = batPose(actT)
        case .scoop: p = batPose(actT, up: true)
        case .bunnyKick: p = bunnyKickPose(actT)
        case .hunt, .goTreat: p = sitPose()
        case .stalk:
            if let m = critter, abs(m.x - x) > 480 { p = standPose(phase: phase, amp: 1, crouch: 0.5); p.eyes = .wide }
            else { p = crawlPose(actT); p.earFlat = 0.1; p.tail[3] = p.tail[3].off(0, CGFloat(sin(time * 7)) * 3) }
        case .alert:
            p = standPose(phase: 0, amp: 0, crouch: 0.15)
            p.headC = p.headC.off(1, 3); p.eyes = .wide; p.earFlat = -0.25
            p.tail[3] = p.tail[3].off(0, CGFloat(sin(time * 10)) * 3)
        case .chaseMouse: p = standPose(phase: phase, amp: 1, run: true); p.eyes = .wide
        case .pounceMouse: p = airPose()
        case .eatTreat: p = eatPose(actT, false, bowl: false)
        case .exitTo: p = standPose(phase: phase, amp: 1)
        case .dig: p = digPose(actT)
        case .strain: p = strainPose()
        case .deepSleep: p = sleepPose()
        case .claw: p = clawPose(actT)
        case .brushed:   // back raised into the brush, eyes squeezed happy, tail up and quivering
            p = standPose(phase: 0, amp: 0)
            p.bodyC = p.bodyC.off(0, 2); p.bodyH += 3; p.bodyRot = 0.05
            p.headC = p.headC.off(1, 3); p.headTilt = 0.15 * CGFloat(sin(time * 2)); p.eyes = .happy
            p.tail = tailUp(P(-25, 27)); p.tail[3] = p.tail[3].off(CGFloat(sin(time * 20)), 0)
        case .hairball: p = hairballPose(actT)
        case .leapCatch: p = airPose()
        case .hang: p = hangPose(actT)
        case .pullUp: p = climbPose(actT)
        }
        if case .window = surface, p.tail.count == 4 {
            switch act {
            case .sit, .loaf, .sleep, .deepSleep, .groom, .scratch, .petted, .lookUp, .yawn, .meow, .annoyed, .face:
                let b = p.tail[0], sway = CGFloat(sin(time * 1.3)) * 3
                p.tail = [b, b.off(-7, -5), b.off(-6, -20), b.off(-3 + sway, -33)]
                p.tailFront = false
            default: break
            }
        }
        if time - lastMeowAt < 0.6 && p.mouth == .none && !isSleeping { p.mouth = .meow }
        if time < startleUntil && !isSleeping {   // startled: wide eyes, ears up, puffed tail
            p.eyes = .wide; p.earFlat = -0.25; p.tailW = 10
        }
        if time < tiltUntil { p.headTilt += 0.4 }  // curious head tilt
        if (p.eyes == .open || p.eyes == .half) && time < blinkUntil { p.eyes = .closed }
        return p
    }

    func tailUp(_ base: CGPoint) -> [CGPoint] {
        let w = CGFloat(sin(time * 3)) * 2
        return [base, base.off(-7, 14), base.off(-9, 32), base.off(-1 + w, 38)]
    }

    func standPose(phase ph: CGFloat, amp: CGFloat, crouch c: CGFloat = 0, run: Bool = false) -> Pose {
        var p = Pose()
        let bob = amp > 0 ? abs(sin(ph)) * (run ? 3 : 1.5) : 0
        let h = 22 - c * 9 + bob
        p.bodyC = P(0, h); p.bodyW = run ? 58 : 54; p.bodyH = 24 - c * 2
        let hipY = h - 3, sw: CGFloat = run ? 13 : 7
        func leg(_ hx: CGFloat, _ off: CGFloat, far: Bool, back: Bool) -> Limb {
            let a = ph + off
            let swing = sin(a) * sw * amp
            let lift = max(0, cos(a)) * (run ? 8 : 4) * amp
            let foot = P(hx + swing, lift)
            let midY = (hipY + lift) / 2
            let knee = back ? P(hx + swing * 0.4 - 4 - c * 6, midY + 1) : P(hx + swing * 0.5 + c * 6, midY)
            return Limb(hip: P(hx, hipY), foot: foot, knee: knee, far: far)
        }
        p.legs = [leg(13, .pi, far: true, back: false), leg(-20, 0, far: true, back: true),
                  leg(17, 0, far: false, back: false), leg(-15, .pi, far: false, back: true)]
        p.headC = P(29 + c * 4, h + 18 - c * 7 + (amp > 0 ? sin(ph * 2) * 0.8 : 0))
        let base = P(-25, h + 5)
        let wave = CGFloat(sin(time * 2.2)) * 5
        if c > 0.3 || run {
            p.tail = [base, base.off(-14, -1), base.off(-26, 3 + wave), base.off(-38, 6 + wave)]
        } else {
            p.tail = [base, base.off(-12, 8), base.off(-22, 28), base.off(-14 + wave, 38)]
        }
        return p
    }

    func sitPose() -> Pose {
        var p = Pose()
        p.bodyC = P(-3, 24); p.bodyW = 46; p.bodyH = 30; p.bodyRot = 1.2
        p.haunchC = P(-11, 13); p.haunchR = 14
        p.headC = P(6, 48)
        p.legs = [Limb(hip: P(1, 28), foot: P(2, 0), far: true),
                  Limb(hip: P(6, 28), foot: P(8, 0)),
                  Limb(hip: P(-13, 5), foot: P(-3, 0), w: 8)]
        let flick = CGFloat(max(0, sin(time * 1.7))) * 5
        p.tail = [P(-22, 8), P(-36, 0), P(-18, -5), P(14, 1 + flick)]
        p.tailFront = true
        return p
    }

    func lookUpPose() -> Pose {
        var p = sitPose()
        p.headC = p.headC.off(1, 3); p.eyes = .wide
        p.tail = tailUp(P(-20, 14)); p.tailFront = false
        return p
    }

    func waitBowlPose(_ t: Double) -> Pose {
        var p = sitPose()
        let cyc = t.truncatingRemainder(dividingBy: 4)
        if cyc < 1.2 {   // paw at the empty bowl
            let ft = CGFloat(cyc)
            p.legs[1] = Limb(hip: P(6, 28), foot: P(26 + sin(ft * 10) * 3, 6 + abs(sin(ft * 10)) * 4), knee: P(17, 18))
            p.headTilt = -0.2
        } else {
            p.tail[3] = p.tail[3].off(0, CGFloat(sin(time * 6)) * 4)   // impatient tail flick
        }
        return p
    }

    func loafPose() -> Pose {
        var p = Pose()
        p.bodyC = P(0, 15); p.bodyW = 56; p.bodyH = 29
        p.headC = P(23, 29); p.eyes = .half
        p.legs = [Limb(hip: P(16, 5), foot: P(21, 1), w: 7)]
        p.tail = [P(-26, 6), P(-32, -1), P(-6, -3), P(16, 0)]
        p.tailFront = true
        return p
    }

    func sleepPose() -> Pose {
        var p = Pose()
        let br = 1 + 0.06 * CGFloat(sin(time * 1.9))
        p.bodyC = P(-3, 12 * br); p.bodyW = 60; p.bodyH = 24 * br
        p.headC = P(19, 12); p.headR = 13; p.headTilt = -0.2; p.eyes = .closed
        p.legs = [Limb(hip: P(12, 6), foot: P(27, 2), w: 7)]
        p.tail = [P(-30, 6), P(-37, -3), P(0, -5), P(26, 1)]
        p.tailFront = true
        return p
    }

    /// Grooming alternates between licking a raised paw and sweeping the damp paw over the ear and face.
    /// The working paw is drawn in front of the face so it reads clearly.
    func groomPose(_ t: Double) -> Pose {
        var p = sitPose()
        let ft = CGFloat(t), cyc = t.truncatingRemainder(dividingBy: 7)
        let hc = p.headC
        p.eyes = .closed
        p.legs.remove(at: 1)
        if cyc < 3 {
            let lick = sin(ft * 9)
            p.frontLimb = Limb(hip: P(6, 30), foot: P(14, hc.y - 9 + lick * 1.5), knee: P(18, 32))
            p.headC = hc.off(1, -2 - max(0, lick) * 1.5); p.headTilt = -0.15
            p.mouth = lick > 0 ? .tongue : .none
        } else {
            let a = ft * 4.5
            p.frontLimb = Limb(hip: P(6, 30), foot: hc.off(3 + cos(a) * 7, 4 + sin(a) * 8), knee: P(16, 38))
            p.headTilt = -0.3 + sin(a) * 0.15
            p.earFlat = 0.25 + max(0, sin(a)) * 0.3
        }
        return p
    }

    func scratchPose(_ t: Double) -> Pose {
        var p = sitPose()
        let ft = CGFloat(t)
        p.bodyRot = 1.35; p.headTilt = 0.3; p.eyes = .happy; p.earFlat = 0.3
        p.legs.removeLast()
        p.legs.append(Limb(hip: P(-10, 12), foot: P(-7 + sin(ft * 30) * 3, 45 + cos(ft * 30) * 3), knee: P(8, 24), w: 8))
        return p
    }

    /// Front stretch: chest down, butt up, paws reaching forward.
    func stretchPose(_ t: Double) -> Pose {
        let s = CGFloat(sin(.pi * min(t / 2.6, 1)))
        var p = standPose(phase: 0, amp: 0)
        p.bodyRot = -0.28 * s; p.bodyC = P(-2, 22 - 3 * s)
        p.legs[0] = Limb(hip: P(12, 18 - 6 * s), foot: P(12 + 18 * s, 0), far: true)
        p.legs[2] = Limb(hip: P(16, 18 - 6 * s), foot: P(16 + 18 * s, 0))
        p.headC = P(29 + 8 * s, 40 - 20 * s)
        p.eyes = s > 0.5 ? .closed : .open
        p.tail = [P(-25, 27), P(-34, 36), P(-38, 52), P(-30, 62)]
        return p
    }

    /// Halloween-cat arch: legs straight and gathered, back bowed up high.
    func archPose(_ t: Double) -> Pose {
        let s = CGFloat(sin(.pi * min(t / 2.4, 1)))
        var p = Pose()
        p.bodyC = P(0, 24 + 9 * s); p.bodyW = 54 - 8 * s; p.bodyH = 24 + 8 * s
        let hipY = p.bodyC.y - 4
        p.legs = [Limb(hip: P(12 - 2 * s, hipY), foot: P(12 - 6 * s, 0), far: true),
                  Limb(hip: P(-18 + 2 * s, hipY), foot: P(-18 + 7 * s, 0), far: true),
                  Limb(hip: P(16 - 2 * s, hipY), foot: P(16 - 6 * s, 0)),
                  Limb(hip: P(-14 + 2 * s, hipY), foot: P(-14 + 7 * s, 0))]
        p.headC = P(28 - 3 * s, 40 - 2 * s)
        p.eyes = s > 0.5 ? .closed : .open
        p.earFlat = 0.3 * s
        p.tail = tailUp(P(-24 + 4 * s, 26 + 6 * s))
        return p
    }

    /// The full Halloween-cat arch: up on stiff, gathered legs, spine bowed high, head tucked, tail straight up
    /// and puffed. Rises, holds with a little tremble, then melts back down.
    func bigArchPose(_ t: Double) -> Pose {
        let rise = min(t / 0.7, 1), fall = max(0, (t - 2.6) / 0.6)
        let k0 = CGFloat(rise - fall), k = k0 * k0 * (3 - 2 * k0)
        let tr = (t > 0.7 && t < 2.6) ? CGFloat(sin(t * 40)) * 0.6 : 0
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { P(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k) }
        var p = Pose()
        // body lifts high on straight legs (clear gap under the belly) with a hump on top for the bowed spine
        p.bodyC = mix(P(0, 22), P(0, 34 + tr)); p.bodyW = 54 - 14 * k; p.bodyH = 24 - 2 * k
        p.haunchC = mix(P(0, 22), P(0, 45 + tr)); p.haunchR = 8 + 5 * k
        p.legs = [Limb(hip: mix(P(13, 19), P(9, 30)), foot: mix(P(13, 0), P(5, 0)), far: true),
                  Limb(hip: mix(P(-20, 19), P(-15, 30)), foot: mix(P(-20, 0), P(-10, 0)), far: true),
                  Limb(hip: mix(P(17, 19), P(12, 30)), foot: mix(P(17, 0), P(8, 0))),
                  Limb(hip: mix(P(-15, 19), P(-12, 30)), foot: mix(P(-15, 0), P(-7, 0)))]
        p.headC = mix(P(29, 40), P(24, 30)); p.headTilt = -0.25 * k
        p.eyes = k > 0.5 ? .closed : .open; p.earFlat = 0.45 * k
        p.mouth = (t > 1.2 && t < 2.2) ? .meow : .none                              // a big yawn at the peak
        let b = mix(P(-25, 27), P(-18, 38))
        p.tail = [b, b.off(-9, 8), b.off(-13, 24), b.off(-9 + tr, 36)]
        p.tailW = 6.4 + 4 * k                                                       // puffed up
        return p
    }

    /// Back-leg stretch: one hind leg pushed straight out behind and held.
    func legStretchPose(_ t: Double) -> Pose {
        let s = CGFloat(sin(.pi * min(t / 2.0, 1)))
        var p = standPose(phase: 0, amp: 0)
        p.bodyRot = 0.1 * s; p.bodyC = P(2 * s, 23)
        p.legs[3] = Limb(hip: P(-15, 20), foot: P(-15 - 24 * s, 4 + 8 * s))
        p.headC = P(30 + 2 * s, 42 + 2 * s)
        p.eyes = s > 0.6 ? .happy : .open
        p.tail = [P(-25, 27), P(-36, 30), P(-44, 34), P(-52, 32)]
        return p
    }

    func yawnPose(_ t: Double) -> Pose {
        var p = sitPose()
        let open = t > 0.2 && t < 1.3
        p.headC = p.headC.off(0, open ? 3 : 0)
        p.eyes = open ? .closed : .half
        p.mouth = open ? .meow : .none
        p.earFlat = open ? 0.4 : 0
        return p
    }

    func crouchPose(_ t: Double) -> Pose {
        var p = standPose(phase: 0, amp: 0, crouch: 1)
        let w = CGFloat(sin(t * 14))
        p.bodyRot = w * 0.06                         // the butt wiggle
        p.legs[1].hip = p.legs[1].hip.off(w * 2.5, 0)
        p.legs[3].hip = p.legs[3].hip.off(w * 2.5, 0)
        p.tail[3] = p.tail[3].off(0, w * 5)
        p.eyes = .wide
        return p
    }

    func crawlPose(_ t: Double) -> Pose {
        var p = Pose()
        let ft = CGFloat(t)
        let sh = sin(ft * 15) * 1.6
        p.bodyC = P(sh, 9); p.bodyW = 60; p.bodyH = 15; p.bodyRot = sin(ft * 15) * 0.04
        let sw = sin(phase) * 6
        p.legs = [Limb(hip: P(14, 6), foot: P(22 - sw, 0), knee: P(11, 11), far: true),
                  Limb(hip: P(-20 + sh, 6), foot: P(-12 + sw, 0), knee: P(-26 + sh, 10), far: true),
                  Limb(hip: P(18, 6), foot: P(26 + sw, 0), knee: P(15, 12)),
                  Limb(hip: P(-16 + sh, 6), foot: P(-8 - sw, 0), knee: P(-22 + sh, 11))]
        p.headC = P(32, 12); p.headR = 13; p.earFlat = 0.85; p.eyes = .wide
        let wag = CGFloat(sin(time * 4)) * 3
        p.tail = [P(-28 + sh, 9), P(-40, 8), P(-52, 6 + wag), P(-63, 4 + wag)]
        return p
    }

    func airPose() -> Pose {
        var p = Pose()
        p.shadow = false
        p.bodyC = P(0, 24); p.bodyW = 62; p.bodyH = 22
        p.bodyRot = clampf(atan2(vy, abs(vx) + 250) * 0.5, -0.45, 0.45)
        p.headC = P(32, 36 + p.bodyRot * 18)
        if vy > 0 {
            p.legs = [Limb(hip: P(13, 21), foot: P(32, 30), far: true), Limb(hip: P(-20, 21), foot: P(-40, 10), far: true),
                      Limb(hip: P(17, 21), foot: P(36, 26)), Limb(hip: P(-15, 21), foot: P(-36, 6))]
        } else {
            p.legs = [Limb(hip: P(13, 21), foot: P(22, 1), far: true), Limb(hip: P(-20, 21), foot: P(-28, 5), far: true),
                      Limb(hip: P(17, 21), foot: P(27, 2)), Limb(hip: P(-15, 21), foot: P(-23, 3))]
        }
        p.tail = [P(-28, 26 - p.bodyRot * 10), P(-42, 31 - p.bodyRot * 16), P(-54, 26 - p.bodyRot * 22), P(-65, 31 - p.bodyRot * 28)]
        return p
    }

    /// Crouched and leaning in over the bowl, head dipped inside it (the app draws the bowls in front of the cat
    /// while it eats, so the rim hides its chin). Food: dip, grab a mouthful, crunch; every few seconds the head
    /// comes up out of the bowl to chew and glance around. Water: head low, eyes half shut, quick lapping bobs.
    /// `bowl: false` (a treat on the floor) drops the head all the way down.
    func eatPose(_ t: Double, _ water: Bool, bowl: Bool = true) -> Pose {
        var p = standPose(phase: 0, amp: 0, crouch: 0.1)
        let ft = CGFloat(t), low: CGFloat = bowl ? 0 : -13
        p.bodyRot = -0.2                                     // shoulders dipped lower than the hips
        p.legs[0].foot.x += 4; p.legs[2].foot.x += 4         // front paws planted forward, by the bowl
        let tip = CGFloat(sin(time * 1.6)) * 3               // tail held out behind in a relaxed curve, tip twitching
        p.tail = [P(-25, 22), P(-38, 24), P(-47, 32), P(-46 + tip, 42)]
        if water {
            let lap = sin(ft * 13)
            p.headC = P(32, 33 + low + CGFloat(max(0, lap)) * 1.5)
            p.eyes = .half; p.earFlat = 0.12
            p.mouth = lap > 0 ? .tongue : .none
        } else if t.truncatingRemainder(dividingBy: 5) < 3.6 {
            let bite = sin(ft * 5)
            p.headC = P(32, 26 + low + CGFloat(max(0, bite)) * 4)
            p.eyes = .closed
            p.mouth = bite > 0.3 ? .chew : .none
        } else {   // up out of the bowl for a moment: chew, chew, look around
            p.headC = P(30, 38 + low)
            p.eyes = .half; p.headTilt = CGFloat(sin(ft * 2)) * 0.12
            p.mouth = sin(ft * 12) > 0 ? .chew : .none
            p.earFlat = CGFloat(sin(ft * 3)) * 0.15
        }
        return p
    }

    /// Low, focused, one front paw swiping out at the yarn (or scooping it up into the air).
    func batPose(_ t: Double, up: Bool = false) -> Pose {
        var p = standPose(phase: 0, amp: 0, crouch: 0.4)
        let k = CGFloat(sin(.pi * min(t / 0.45, 1)))
        p.legs[2] = up ? Limb(hip: P(17, 17), foot: P(24 + 4 * k, 3 + 22 * k), knee: P(25, 12))
                       : Limb(hip: P(17, 17), foot: P(20 + 18 * k, 3 + 9 * k), knee: P(22 + 6 * k, 13))
        p.eyes = .wide; p.earFlat = 0.15
        p.headC = p.headC.off(2 * k, -1)
        return p
    }

    /// Flopped on its back, front paws hugging the yarn up on its chest, back feet kicking it like mad.
    func bunnyKickPose(_ t: Double) -> Pose {
        var p = Pose()
        let ft = CGFloat(t), k1 = (sin(ft * 24) + 1) / 2, k2 = (sin(ft * 24 + 2) + 1) / 2
        p.bodyC = P(-6, 10); p.bodyW = 50; p.bodyH = 18; p.bodyRot = 0.08
        p.headC = P(22, 13); p.headTilt = 0.3; p.eyes = .wide; p.earFlat = 0.5
        p.legs = [Limb(hip: P(10, 16), foot: P(8, 34), knee: P(4, 26), far: true),
                  Limb(hip: P(-18, 14), foot: P(-2 + 6 * k2, 22 + 8 * k2), knee: P(-20, 30), far: true),
                  Limb(hip: P(14, 16), foot: P(26, 34), knee: P(24, 26), far: true)]
        // the near back leg is drawn on top with its own outline so the kicking reads on any coat
        p.frontLimb = Limb(hip: P(-14, 14), foot: P(2 + 6 * k1, 20 + 8 * k1), knee: P(-14, 31))
        let w = CGFloat(sin(time * 9)) * 4
        p.tail = [P(-30, 6), P(-40, 3), P(-50, 5 + w), P(-60, 2 - w)]
        p.shadow = true
        return p
    }

    /// Facing off the screen, back feet scraping litter backwards.
    func digPose(_ t: Double) -> Pose {
        var p = standPose(phase: 0, amp: 0, crouch: 0.3)
        let ft = CGFloat(t), k1 = max(0, sin(ft * 14)), k2 = max(0, -sin(ft * 14))
        p.legs[1] = Limb(hip: P(-20, 17), foot: P(-22 - 22 * k2, 10 * k2), knee: P(-26 - 8 * k2, 10 + 2 * k2), far: true)
        p.legs[3] = Limb(hip: P(-15, 17), foot: P(-17 - 22 * k1, 10 * k1), knee: P(-21 - 8 * k1, 10 + 2 * k1))
        p.tail = tailUp(P(-25, 26))
        return p
    }

    /// Dangling from a window's top edge: front paws hooked over it, chin at the edge, back feet scrabbling
    /// against the window, tail hanging. `lift` (0…1) starts hauling the body up and over.
    func hangPose(_ t: Double, lift: CGFloat = 0) -> Pose {
        var p = Pose()
        let E = Cat.hangEdge, ft = CGFloat(t)
        let k1 = (sin(ft * 18) + 1) / 2, k2 = (sin(ft * 18 + 2.4) + 1) / 2
        let scrabble: CGFloat = 1 - lift
        p.shadow = false
        p.bodyC = P(-2 + 6 * lift, 34 + 10 * lift); p.bodyW = 46; p.bodyH = 26; p.bodyRot = 1.45 - 0.7 * lift
        p.headC = P(6 + 4 * lift, E - 6 + 4 * lift); p.eyes = lift > 0 ? .closed : .wide; p.earFlat = 0.3
        // paws spread wide along the edge on either side of the head
        p.legs = [Limb(hip: P(-2, 46), foot: P(-22, E + 1), knee: P(-16, 52), far: true),
                  Limb(hip: P(-6, 18), foot: P(-1 + 6 * k2 * scrabble, 6 + 9 * k2 * scrabble), knee: P(-12, 12), far: true),
                  Limb(hip: P(14, 44), foot: P(33, E + 1), knee: P(30, 50)),
                  Limb(hip: P(-3, 18), foot: P(2 + 6 * k1 * scrabble, 4 + 9 * k1 * scrabble), knee: P(-9, 10))]
        let sway = CGFloat(sin(time * 2.2)) * 3
        p.tail = [P(-8, 18), P(-12, 6), P(-8, -6), P(-12 + sway, -18)]
        return p
    }

    /// Climbing up from the hang. Every point is placed relative to the window's top edge, which sits
    /// `Cat.climbEdge(t)` above the feet anchor, so the front paws stay planted on the edge while the body moves:
    /// first the cat hauls its chest up to the edge (elbows bending, head over the top, back feet scrabbling),
    /// then it tips forward over the edge and brings its back legs up, ending crouched on top.
    func climbPose(_ t: Double) -> Pose {
        let (a, b) = Cat.climbPhases(t)
        let edge = Cat.climbEdge(t)
        let hang = hangPose(t).shifted(-Cat.hangEdge)          // the hang, with the edge at y = 0
        var chest = Pose()                                      // chest hauled up level with the edge
        chest.bodyC = P(4, -10); chest.bodyW = 46; chest.bodyH = 26; chest.bodyRot = 1.05
        chest.headC = P(16, 13); chest.eyes = .strain; chest.earFlat = 0.35
        let ft = CGFloat(t), k1 = (sin(ft * 20) + 1) / 2, k2 = (sin(ft * 20 + 2.4) + 1) / 2
        chest.legs = [Limb(hip: P(10, -2), foot: P(33, 1), knee: P(4, 9), far: true),           // forearms flat on the top
                      Limb(hip: P(-6, -28), foot: P(-2 + 5 * k2, -44 + 8 * k2), knee: P(-13, -36), far: true),
                      Limb(hip: P(14, -2), foot: P(41, 1), knee: P(9, 8)),
                      Limb(hip: P(-3, -28), foot: P(1 + 5 * k1, -46 + 8 * k1), knee: P(-10, -38))]
        chest.tail = [P(-6, -26), P(-11, -38), P(-7, -50), P(-11, -62)]
        chest.shadow = false
        var top = standPose(phase: 0, amp: 0, crouch: 0.7)      // crouched on top of the window
        top.eyes = .open
        var p = b > 0 ? chest.mix(top, b) : hang.mix(chest, a)
        p = p.shifted(edge)
        p.shadow = edge < 1
        return p
    }

    /// Rears up from all fours into a long stretch against a window's side edge, then rakes its claws
    /// down it one paw at a time, eyes shut in bliss.
    func clawPose(_ t: Double) -> Pose {
        let r = CGFloat(min(t / 0.5, 1)), e = r * r * (3 - 2 * r)   // eased rise
        let ft = CGFloat(t), k1 = (sin(ft * 9) + 1) / 2, k2 = (sin(ft * 9 + .pi) + 1) / 2
        let rk1 = k1 * e, rk2 = k2 * e
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint { P(a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e) }
        var p = Pose()
        p.bodyC = mix(P(0, 22), P(2, 34)); p.bodyW = 54 - 2 * e; p.bodyH = 24; p.bodyRot = 1.2 * e
        p.headC = mix(P(29, 40), P(10, 52)); p.headTilt = 0.1 * e
        p.eyes = e > 0.8 ? .closed : .open; p.earFlat = 0.2 * e
        // forelegs reach up from behind the head, paws high above it on the window edge
        p.legs = [Limb(hip: mix(P(13, 19), P(8, 46)), foot: mix(P(13, 0), P(35, 88 - 14 * rk2)), knee: mix(P(13, 9), P(27, 70 - 4 * rk2)), far: true),
                  Limb(hip: P(-10, 16), foot: P(-9, 0), knee: P(-3, 9), far: true),
                  Limb(hip: P(-6, 16), foot: P(-4, 0), knee: P(2, 9))]
        let near = Limb(hip: mix(P(17, 19), P(12, 46)), foot: mix(P(17, 0), P(38, 85 - 14 * rk1)), knee: mix(P(17, 9), P(30, 67 - 4 * rk1)))
        p.legs.append(near)
        p.tail = tailUp(mix(P(-25, 27), P(-10, 22)))
        p.tail[3] = p.tail[3].off(CGFloat(sin(time * 4)) * 3, 0)
        return p
    }

    /// Neck stretched low, body heaving in three hacks, mouth open on the last.
    func hairballPose(_ t: Double) -> Pose {
        var p = standPose(phase: 0, amp: 0, crouch: 0.5)
        let ft = CGFloat(t), heave = max(0, sin(ft * 7))
        p.bodyC = p.bodyC.off(0, heave * 3); p.bodyH += heave * 3
        p.headC = P(37 + heave * 2, 17 - heave * 2); p.headTilt = -0.2
        p.eyes = .strain; p.earFlat = 0.5
        p.mouth = t > 2.2 ? .meow : (heave > 0.6 ? .meow : .none)
        p.tail = [P(-25, 17), P(-36, 12), P(-44, 6), P(-52, 2)]
        return p
    }

    /// Hunched and concentrating very hard.
    func strainPose() -> Pose {
        var p = sitPose()
        p.bodyRot = 1.05; p.headC = p.headC.off(2, -4)
        p.eyes = .strain; p.earFlat = 0.55
        p.tail = tailUp(P(-20, 14)); p.tailFront = false
        return p
    }

    func carriedPose() -> Pose {
        var p = Pose()
        p.shadow = false
        let sway = CGFloat(sin(time * 3)) * 2
        p.bodyC = P(0, 40); p.bodyW = 46; p.bodyH = 28; p.bodyRot = 1.57
        p.headC = P(0, 68); p.eyes = .wide; p.earFlat = 0.3
        p.legs = [Limb(hip: P(5, 52), foot: P(9, 32), far: true), Limb(hip: P(-3, 52), foot: P(-1, 31)),
                  Limb(hip: P(5, 24), foot: P(5 + sway, 2), far: true), Limb(hip: P(-4, 24), foot: P(-4 + sway, 1))]
        p.tail = [P(-2, 22), P(-8, 8), P(4, 0), P(-4 - sway * 3, -12)]
        p.tailFront = true
        return p
    }
}
