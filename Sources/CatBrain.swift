// DesktopCat — how the cat decides what to do next.

import Cocoa

extension Cat {
    // MARK: brain

    func decide() {
        var plan: [Act] = []
        let patient = time - lastWait > 60 || chance(0.5)
        if treat != nil && time > treatGiveUpUntil { queue = [.goTreat]; return }
        if critter != nil && chance(0.85) { queue = [.hunt(0)]; return }
        if s.hydration < 0.4 && (s.water > 0.03 || patient) { plan = planBowl(true) }
        else if s.belly < 0.4 && (s.food > 0.03 || patient) { plan = planBowl(false) }
        else if s.energy < 0.22 { plan = planSleep() }
        else if s.happiness < 0.3 && chance(0.4) { plan = planAttention() }
        else {
            let t = trait
            func m(_ lazy: Double, _ playful: Double, _ clingy: Double, _ skittish: Double, _ curious: Double) -> Double {
                switch t { case .lazy: return lazy; case .playful: return playful; case .clingy: return clingy
                           case .skittish: return skittish; case .curious: return curious }
            }
            let onWin: Bool = { if case .window = surface { return true }; return false }()
            let cursorNear = time - lastMouseMove < 1.5 && abs(mouse.x - x) < 380 && abs(mouse.x - x) > 70 && mouse.y > y - 20 && mouse.y < y + 260
            var opts: [(Double, () -> [Act])] = [
                (18 * m(0.6, 1.2, 1, 0.9, 1.6), wander),
                (12 * m(1.3, 0.8, 1, 1, 1), { [.sit(rndD(3, 8))] }),
                (10, { [.groom(rndD(5, 9))] }),
                (5, { [.scratch(rndD(1.5, 3))] }),
                ((onWin ? 12 : 6) * m(2.5, 0.6, 1, 1, 0.8), { [.loaf(rndD(8, 25))] }),
                ((onWin ? 7 : 16) * m(0.4, 1.3, 0.8, 0.8, 2.2), planJumpUp),
                ((s.energy < 0.5 ? 12 : 4) * m(2.5, 0.6, 1, 1, 0.8), planSleep),
                (6 * m(1.5, 1, 1, 1, 1), { [[.stretch, .legStretch], [.archStretch], [.yawn, .stretch], [.bigArch], [.bigArch, .legStretch]].randomElement()! }),
                (3 * m(1, 1, 2, 0.6, 1), { [.meow, .sit(2)] }),
            ]
            if onWin { opts.append((10, { self.goToFloor() + [.sit(rndD(1, 3))] })) }
            if surface == .floor { opts.append((5 * m(1, 0.6, 0.4, 3.5, 1), planHide)) }
            if toy != nil && s.energy > 0.15 { opts.append((40 * m(0.5, 1.8, 1, 0.8, 1.2), { [.play(0)] })) }
            if s.litterOn && time - lastLitter > 20 * 60 { opts.append((0.6, planLitter)) }   // a regular habit, but never back to back
            if surface == .floor { opts.append((7 * m(0.6, 1.5, 1, 1, 1.5), planClaw)) }
            if s.energy > 0.55 { opts.append((2.5 * m(0.2, 3, 1, 1.4, 1.2), planZoomies)) }
            if cursorNear { opts.append((14 * m(0.5, 2, 1, 0.7, 1.3), planPounce)) }
            if s.happiness < 0.6 || t == .clingy { opts.append((5 * m(1, 1, 3.5, 0.3, 1), planAttention)) }
            if !hairballOut && s.hairballsOn {   // rare, a bit likelier for long coats and matted fur
                opts.append((0.08 * (fluffy ? 1.8 : 1) * (s.coatCare < 0.35 ? 3 : 1), { [.hairball(rndD(2.6, 3.4))] }))
            }
            let total = opts.reduce(0) { $0 + $1.0 }
            var r = Double.random(in: 0..<total)
            for (w, f) in opts { if r < w { plan = f(); break }; r -= w }
        }
        if plan.isEmpty { plan = [.sit(rndD(2, 5))] }
        queue = plan
    }

    func wakeStretches() -> [Act] {
        [[.yawn, .stretch, .legStretch], [.stretch, .archStretch], [.yawn, .archStretch], [.stretch], [.yawn, .bigArch], [.bigArch, .stretch]].randomElement()!
    }

    func wander() -> [Act] {
        let r = range()
        guard r.1 - r.0 > 40 else { return [] }
        var tx = rnd(r.0, r.1)
        if abs(tx - x) < 60 { tx = clampf(x + (tx > x ? 120 : -120), r.0, r.1) }
        return [.walk(tx, rnd(55, 85)), .sit(rndD(1.5, 5))]
    }

    func planZoomies() -> [Act] {
        let r = range()
        guard r.1 - r.0 > 200 else { return [] }
        var p: [Act] = [.crouch(0.4)]
        for _ in 0..<Int.random(in: 3...5) { p.append(.walk(rnd(r.0, r.1), rnd(260, 320))) }
        if surface == .floor && chance(0.5) { p += planJumpUp() }
        p.append(.sit(2))
        return p
    }

    func planPounce() -> [Act] {
        let dir: CGFloat = mouse.x > x ? 1 : -1
        return [.face(dir), .crouch(rndD(1, 1.8)), .leap(P(mouse.x, max(mouse.y, y))), .sit(1.5)]
    }

    /// Trot over to the cursor with tail held high and gaze up, mewing.
    func planAttention() -> [Act] {
        let r = range()
        let tx = clampf(mouse.x + (mouse.x > x ? -60 : 60), r.0, r.1)
        return [.walk(tx, 75), .face(mouse.x > tx ? 1 : -1), .lookUp(rndD(3, 5))]
    }

    func landingX(_ p: Plat, near: CGFloat) -> CGFloat? {
        let lo = max(p.rect.minX, world.vis.minX) + 40, hi = min(p.rect.maxX, world.vis.maxX) - 40
        guard hi > lo else { return nil }
        var best: CGFloat? = nil
        for _ in 0..<12 {
            let c = rnd(lo, hi)
            if world.topVisible(p, c) && (best == nil || abs(c - near) < abs(best! - near)) { best = c }
        }
        return best
    }

    func canReach(from fy: CGFloat, _ p: Plat) -> Bool { let d = p.top - fy; return abs(d) > 40 && d <= maxJumpUp }

    /// Walk to a spot under/next to `p`, wiggle, and leap onto it. Empty if out of reach from here.
    func jumpTo(_ p: Plat) -> [Act] {
        guard canReach(from: y, p), let lx = landingX(p, near: x) else { return [] }
        let r = range()
        let side: CGFloat = lx >= x ? 1 : -1
        let tx = clampf(lx - side * rnd(50, 110), r.0, r.1)
        guard abs(lx - tx) < 360 else { return [] }
        return [.walk(tx, rnd(70, 95)), .face(lx >= tx ? 1 : -1), .crouch(rndD(0.8, 1.6)), .leapOn(p.id, lx - p.rect.minX)]
    }

    func planJumpUp() -> [Act] {
        var cur: CGWindowID = 0
        if case .window(let id) = surface { cur = id }
        let others = world.stand.filter { $0.id != cur }
        guard let target = others.randomElement() else { return [] }
        let direct = jumpTo(target)
        if !direct.isEmpty { return direct + [.sit(rndD(1, 3))] }
        // Too high to reach in one bound: hop onto a lower window first, then on up.
        for mid in others.shuffled() where mid.id != target.id && canReach(from: y, mid) && canReach(from: mid.top, target) {
            let first = jumpTo(mid)
            if !first.isEmpty { return first + [.sit(rndD(0.5, 1.5)), .goTo(target.id), .sit(rndD(1, 3))] }
        }
        return [.lookUp(2)]   // gaze longingly at the unreachable window
    }

    func goToFloor() -> [Act] {
        guard case .window = surface else { return [] }
        let v = world.vis, rc = surfRect, r = range()
        let canRight = rc.maxX < v.maxX - 60, canLeft = rc.minX > v.minX + 60
        let right = canRight && (!canLeft ? true : chance(0.5))
        let edge = right ? r.1 : r.0
        let land = right ? min(rc.maxX + rnd(40, 110), v.maxX - 40) : max(rc.minX - rnd(40, 110), v.minX + 40)
        return [.walk(edge, 85), .face(right ? 1 : -1), .crouch(0.5), .leap(P(land, world.floorY))]
    }

    func planBowl(_ water: Bool, hurry: Bool = false) -> [Act] {
        let bx = water ? world.waterX : world.foodX
        let level = water ? s.water : s.food
        return goToFloor() + [.walk(bx - 33 * cs, hurry ? 240 : 90), .face(1), level > 0.03 ? .eat(water) : .waitBowl(water)]
    }

    func planSleep() -> [Act] {
        let nap = Act.sleep(s.energy < 0.3 ? rndD(120, 300) : rndD(45, 150))
        if case .window = surface { return [.loaf(rndD(2, 5)), nap] }
        if chance(0.35) { let up = jumpToAny(); if !up.isEmpty { return up + [.loaf(3), nap] } }
        if chance(0.3) { let h = planHide(); if !h.isEmpty { return h } }
        return [.loaf(rndD(2, 5)), nap]
    }

    func jumpToAny() -> [Act] {
        for p in world.stand.shuffled() { let j = jumpTo(p); if !j.isEmpty { return j } }
        return []
    }

    /// Crouch, then squeeze-shimmy underneath a window that comes down near the floor, hang out, and crawl back out.
    func planHide() -> [Act] {
        guard surface == .floor else { return [] }
        let fy = world.floorY, v = world.vis
        let cands = world.all.filter { $0.rect.minY <= fy + 40 && $0.rect.width > 240 && $0.rect.maxY > fy + 120 }
        guard let p = cands.randomElement() else { return [] }
        var opts: [(edge: CGFloat, dir: CGFloat)] = []
        if p.rect.minX > v.minX + 70 { opts.append((p.rect.minX, 1)) }
        if p.rect.maxX < v.maxX - 70 { opts.append((p.rect.maxX, -1)) }
        guard let o = opts.min(by: { abs($0.edge - x) < abs($1.edge - x) }) else { return [] }
        let outside = o.edge - o.dir * 55, inside = o.edge + o.dir * 90
        return [.walk(outside, 75), .face(o.dir), .crouch(0.7), .crawl(inside, p.id), .hide(p.id, rndD(20, 70)),
                .face(-o.dir), .crawl(outside, p.id), .sit(2)]
    }
}
