// DesktopCat — petting, brushing, carrying, treats, toys, mice and other reactions.

import Cocoa

extension Cat {
    // MARK: interactions

    func pet() {
        guard !isAirborne, !isHidden else { return }
        s.happiness = min(1, s.happiness + 0.06)
        petTimes = petTimes.filter { time - $0 < 10 } + [time]
        if petTimes.count >= (trait == .clingy ? 13 : 8) {   // overstimulated: ears back, a quick swat, then off they go
            petTimes = []
            let dir: CGFloat = chance(0.5) ? 1 : -1
            interrupt([.swat, .hop(dir * 250, 520), .annoyed(rndD(3, 5)), .groom(3)])
            return
        }
        sound.doPurr()
        heart()
        switch act {
        case .sleep, .eat, .waitBowl: break
        case .petted: actT = min(actT, 1)
        default:
            if abs(mouse.x - x) > 4 { facing = mouse.x > x ? 1 : -1 }
            interrupt([.petted(3.2)])
        }
    }

    /// One stroke of the brush across the cat: purrs, leans in, sheds a little fur (more for long coats).
    func brushStroke(at p: CGPoint) {
        guard !isAirborne, !isHidden else { return }
        s.coatCare = min(1, s.coatCare + 0.012); s.happiness = min(1, s.happiness + 0.004)
        strokes += 1
        sound.doPurr()
        for _ in 0..<(lowPower ? 0 : (fluffy ? 3 : 1)) where fur.count < 70 {
            fur.append((p.off(rnd(-6, 6), rnd(-4, 4)), P(rnd(-14, 14), rnd(16, 34)), 0))
        }
        if strokes % 6 == 0 { heart() }
        switch act {
        case .sleep, .deepSleep, .eat, .waitBowl: break
        case .brushed: actT = 0
        default: interrupt([.brushed(1.6)])
        }
    }

    func nudge(from mx: CGFloat) {
        guard !isAirborne, !isHidden else { return }
        let dir: CGFloat = x >= mx ? 1 : -1
        s.happiness = max(0, s.happiness - 0.01)
        startle()
        interrupt([.hop(dir * rnd(240, 300), 560), .face(-dir), .annoyed(rndD(2.5, 4))])
    }

    func startCarry() {
        guard !isHidden else { return }
        queue = []; act = .carried; actT = 0; surface = .air
        meow()
    }

    func carry(to m: CGPoint) { x = m.x; y = m.y - 66 * cs }

    func drop(velocity v: CGPoint) {
        guard case .carried = act else { return }
        queue = [.sit(1), .groom(rndD(2, 4))]
        act = .hop(clampf(v.x * 0.5, -900, 900), clampf(v.y * 0.4, -200, 900)); actT = 0
        ignoreID = 0
    }

    func heardBowl(water: Bool) {
        let need = water ? s.hydration : s.belly
        if isAirborne || isHidden { return }
        if isSleeping {
            if need < 0.6 || chance(0.35) { startle(); interrupt([.yawn] + planBowl(water, hurry: true)) }
            return
        }
        if need < 0.85 { startle(); interrupt(planBowl(water, hurry: true)) } else { tiltUntil = time + 1.2 }
    }

    /// One round of yarn play. Play keeps going until the yarn is knocked off the screen (or the cat is worn out);
    /// swats get stronger as rounds go by, and late in the game they're aimed at the nearest edge.
    func planPlay(_ n: Int) -> [Act] {
        playRound = n
        guard let t = toy, !t.gone else { return [.sit(rndD(1, 2)), .lookUp(1.5), .groom(rndD(2, 4))] }   // where'd it go?
        if s.energy < 0.12 || n > 60 { return [.sit(2), .loaf(rndD(10, 20))] }
        let dir: CGFloat = t.x >= x ? 1 : -1
        if t.held { return [.face(dir), .sit(0.6), .play(n + 1)] }                    // you're holding it — watch intently
        if t.surface == .air { return [.face(dir), .sit(0.5), .play(n + 1)] }          // watch it fly
        if t.surface != surface {
            if t.surface == .floor { let g = goToFloor(); return g.isEmpty ? [.sit(1), .play(n + 1)] : g + [.play(n + 1)] }
            if case .window(let id) = t.surface, let p = world.stand.first(where: { $0.id == id }) {
                let j = jumpTo(p)
                return j.isEmpty ? [.face(dir), .lookUp(1.5), .play(n + 1)] : j + [.play(n + 1)]
            }
            return [.sit(1), .play(n + 1)]
        }
        let dist = abs(t.x - x)
        if dist > 260 { return [.chase(3), .play(n + 1)] }
        if dist > 60 {
            return chance(0.5) ? [.face(dir), .crouch(rndD(0.5, 1.2)), .pounceToy, .bat, .play(n + 1)]
                               : [.chase(2), .bat, .play(n + 1)]
        }
        let r = Double.random(in: 0..<1)
        if r < 0.35 { return [.face(dir), .bunnyKick(rndD(1.8, 3)), .play(n + 1)] }
        if r < 0.55 { return [.face(dir), .crouch(0.4), .scoop, .play(n + 1)] }
        return chance(0.4) ? [.face(dir), .crouch(rndD(0.4, 0.8)), .bat, .play(n + 1)] : [.face(dir), .bat, .play(n + 1)]
    }

    func played() { s.happiness = min(1, s.happiness + 0.02); s.energy = max(0, s.energy - 0.008) }

    func kickToy(_ t: Toy, strong: Bool) {
        let v = world.vis
        var dir = facing
        if playRound > 8 { dir = t.x - v.minX < v.maxX - t.x ? -1 : 1 }   // getting bored: swat it off the screen
        let boost = 1 + CGFloat(min(playRound, 14)) * 0.1
        t.kick(dir * rnd(170, 380) * boost * (strong ? 1.4 : 1), rnd(80, 320))
        played()
    }

    /// The yarn moved (spawned, flicked or thrown) — an awake, idle-ish cat usually comes to play.
    func toyNoticed() {
        guard toy != nil, !isSleeping, !isAirborne, !isHidden, s.energy > 0.15 else { return }
        switch act {
        case .eat, .waitBowl, .play, .chase, .pounceToy, .bat, .scoop, .bunnyKick, .eatTreat, .hunt, .stalk, .chaseMouse: return
        default: break
        }
        if chance(0.85) { startle(); interrupt([.play(0)]) }
    }

    /// Stalk low, wiggle and pounce; once the mouse bolts, run after it until it's gone off the screen.
    func planHunt(_ n: Int) -> [Act] {
        guard let m = critter, !m.gone, n < 14 else {
            return [.sit(rndD(1.5, 2.5)), .annoyed(rndD(1.5, 2.5)), .groom(rndD(2, 4))]   // it got away
        }
        if surface != .floor { let g = goToFloor(); return g.isEmpty ? [.sit(1), .hunt(n + 1)] : g + [.hunt(n + 1)] }
        let dir: CGFloat = m.x >= x ? 1 : -1, dist = abs(m.x - x)
        if m.fleeing { return [.chaseMouse(4), .hunt(n + 1)] }
        if m.x < world.vis.minX || m.x > world.vis.maxX { return [.face(dir), .alert(0.8), .hunt(n + 1)] }   // ears up, waiting
        if dist > 210 { return [.stalk(5), .hunt(n + 1)] }
        return [.face(dir), .crouch(rndD(0.8, 1.6)), .pounceMouse, .hunt(n + 1)]
    }

    func critterNoticed() {
        guard critter != nil, !isAirborne, !isHidden else { return }
        if case .carried = act { return }
        if case .eatTreat = act { return }
        let spot: [Act] = [.face(critter!.x >= x ? 1 : -1), .alert(rndD(1, 1.6)), .hunt(0)]
        if isSleeping {
            if chance(0.5) { interrupt(spot) }
            return
        }
        interrupt(spot)
    }

    func planTreat() -> [Act] {
        guard let t = treat, !t.gone else { return [] }
        let dir: CGFloat = t.x >= x ? 1 : -1
        if t.surface == .air { return [.face(dir), .sit(0.4), .goTreat] }
        if t.surface != surface {
            if t.surface == .floor { let g = goToFloor(); return g + [.goTreat] }
            if case .window(let id) = t.surface, let p = world.stand.first(where: { $0.id == id }) {
                let j = jumpTo(p)
                if !j.isEmpty { return j + [.goTreat] }
            }
            treatGiveUpUntil = time + 30   // can't get there from here: gaze up at it, then try again later
            return [.face(dir), .lookUp(2), .sit(rndD(2, 4))]
        }
        return [.walk(t.x - dir * 28, 210), .face(dir), .eatTreat]
    }

    /// Treats beat everything — even a nap.
    func treatNoticed() {
        guard treat != nil, !isAirborne, !isHidden else { return }
        if case .carried = act { return }
        if isSleeping { interrupt([.yawn, .goTreat]) } else { startle(); interrupt([.goTreat]) }
    }

    /// Walk off the nearest edge of the screen: only the back feet show, kicking litter onto the desktop;
    /// then turn and peek back in, head and shoulders only, straining. Then cover it up and stroll back
    /// (often with post-litter-box zoomies).
    /// Find the nearest window side that comes down to the floor and give it a good scratch.
    func planClaw() -> [Act] {
        guard surface == .floor else { return [] }
        let fy = world.floorY, v = world.vis
        var best: (edge: CGFloat, dir: CGFloat, id: CGWindowID)? = nil
        for p in world.all where p.rect.minY <= fy + 50 && p.rect.maxY >= fy + 100 {
            for (edge, dir) in [(p.rect.minX, CGFloat(1)), (p.rect.maxX, CGFloat(-1))] {
                guard edge > v.minX + 50, edge < v.maxX - 50 else { continue }
                let spot = P(edge - dir * 20, fy + 30), side = P(edge + dir * 2, fy + 55)
                if world.all.contains(where: { $0.rect.contains(spot) }) { continue }                         // room to stand
                if world.all.contains(where: { $0.order < p.order && $0.rect.contains(side) }) { continue }   // edge not covered
                if best == nil || abs(edge - x) < abs(best!.edge - x) { best = (edge, dir, p.id) }
            }
        }
        guard let b = best else { return [] }
        return [.walk(b.edge - b.dir * 39 * cs, 80), .face(b.dir), .claw(b.id, b.edge, rndD(3, 5)),
                chance(0.5) ? .legStretch : .sit(rndD(1, 2))]
    }

    func planLitter() -> [Act] {
        guard surface == .floor || !goToFloor().isEmpty else { return [] }
        lastLitter = time
        let v = world.vis
        let left = x < v.midX
        let out = left ? v.minX - 22 : v.maxX + 22, peek = left ? v.minX - 3 : v.maxX + 3
        let edgeIn = left ? v.minX + 40 : v.maxX - 40
        let back = left ? v.minX + rnd(90, 220) : v.maxX - rnd(90, 220)
        return goToFloor() + [.walk(edgeIn, 80), .exitTo(out), .dig(rndD(2.5, 3.5)), .exitTo(peek), .strain(rndD(4, 6)),
                              .exitTo(out), .dig(rndD(3, 4)), .walk(back, 85)] + (chance(0.6) ? planZoomies() : [.sit(2)])
    }

    /// Menu "Loaf": settle in right here for 30 minutes, nodding off after the first three.
    func loafHere() {
        guard !isAirborne else { return }
        if case .carried = act { return }
        interrupt([.loaf(180), .deepSleep(27.0 * 60)])
    }

    func wakeUp() {
        guard isLongLoaf || isSleeping else { return }
        interrupt(wakeStretches())
    }

    /// Back after vacation mode: wake up if needed, trot over to the cursor and say hello.
    func welcomeBack() {
        guard !isAirborne, !isHidden else { return }
        let wake: [Act] = isSleeping ? [.yawn, .stretch] : []
        interrupt(wake + goToFloor() + [.walk(mouse.x, 120), .lookUp(2.5)])
        heart(); heart(); meow()
    }

    func callOver() {
        guard !isAirborne, !isHidden else { return }
        interrupt(goToFloor() + [.walk(mouse.x, 160), .lookUp(3)])
    }
}
