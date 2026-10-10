// DesktopCat — the cat: state, needs and the action machine.

import Cocoa

// MARK: - The cat

enum Surface: Equatable { case floor, air, window(CGWindowID) }

enum Act {
    case sit(Double), loaf(Double), sleep(Double), groom(Double), scratch(Double)
    case stretch, archStretch, legStretch, yawn          // stretches
    case bigArch                                         // the dramatic Halloween-cat arch
    case meow, annoyed(Double), swat, petted(Double), lookUp(Double)
    case walk(CGFloat, CGFloat)          // target x, speed
    case crawl(CGFloat, CGWindowID)      // flattened shimmy under a window
    case face(CGFloat), crouch(Double), leap(CGPoint), hop(CGFloat, CGFloat), land
    case leapOn(CGWindowID, CGFloat)     // jump onto a window, aiming at minX + offset wherever it is now
    case goTo(CGWindowID)                // plan the next hop toward a window once we've landed
    case hide(CGWindowID, Double)
    case eat(Bool), waitBowl(Bool)       // true = water
    case carried
    case play(Int), chase(Double), pounceToy, bat   // yarn play: plan a round, run after it, pounce, swat
    case bunnyKick(Double), scoop                   // on its back hugging + kicking the yarn; flick it up in the air
    case hunt(Int), stalk(Double), chaseMouse(Double), pounceMouse
    case goTreat, eatTreat
    case exitTo(CGFloat), dig(Double), strain(Double)   // litter box, just off the edge of the screen
    case deepSleep(Double)                              // a long nap that ignores how rested the cat is
    case alert(Double)                                  // spotted something: freeze, ears up
    case leapCatch(CGWindowID, CGFloat)                 // a jump that falls short of a window's top edge…
    case hang(CGWindowID, Double)                       // …front paws hooked over the edge, back feet scrabbling…
    case pullUp(CGWindowID)                             // …and hauling itself up
    case brushed(Double)                                // leaning into the brush
    case claw(CGWindowID, CGFloat, Double)              // up on hind legs scratching a window's side edge
    case hairball(Double)                               // hack… hack… HURK
}

final class Cat {
    let world: World
    var s: SaveState
    let sound: SoundBox

    var x: CGFloat = 400, y: CGFloat = 0, facing: CGFloat = 1
    var surface: Surface = .floor
    var surfRect = CGRect.zero
    var vx: CGFloat = 0, vy: CGFloat = 0
    var ignoreID: CGWindowID = 0, ignoreUntil = 0.0

    var act: Act = .sit(2) {
        didSet {   // whatever ended the last action, don't leave its side effects behind
            if case .bunnyKick = oldValue, !isBunnyKick { toy?.held = false }   // let go of the yarn
            if case .strain = oldValue { shake = 0 }
        }
    }
    var actT = 0.0, queue: [Act] = []
    var isBunnyKick: Bool { if case .bunnyKick = act { return true }; return false }
    var time = 0.0, phase: CGFloat = 0
    var nextBlink = 3.0, blinkUntil = 0.0, lastMeowAt = -9.0
    var startleUntil = -9.0, tiltUntil = -9.0
    var petTimes: [Double] = []
    var hearts: [(p: CGPoint, age: Double, sway: Double)] = []   // screen points
    var mouse = CGPoint.zero, lastMouseMove = -10.0, lastWait = -999.0
    var pose = Pose()
    var toy: Toy?, treat: Toy?, critter: Critter?
    var playRound = 0
    var litter: [(p: CGPoint, v: CGPoint, age: Double)] = []   // screen points
    var shake: CGFloat = 0                                      // 1-pixel tremble while straining
    var catchAt = 0.0, forceCatch = false, forceGrip = false
    var brushMode = false, strokes = 0
    var fur: [(p: CGPoint, v: CGPoint, age: Double)] = []      // shed fur drifting down while brushing (screen points)
    var hairballOut = false
    var onHairball: ((CGPoint, Surface, CGRect) -> Void)?
    var lastScare = -99.0
    var treatGiveUpUntil = -1.0                                 // a treat it can't reach: stop fixating for a while
    var lastLitter = -15.0 * 60   // first trip no sooner than ~5 minutes after launch
    var trait: Personality { Personality(rawValue: s.personality) ?? .curious }
    var fluffy: Bool { coats[s.coat % coats.count].fluff }
    static let hangEdge: CGFloat = 62                           // pose-local height of the window edge while hanging
    static let climbTime = 0.9                                  // hauling up from the hang onto the window top

    /// Climb progress: `a` = hauling the chest up to the edge, then `b` = tipping over onto the top (both eased 0…1).
    static func climbPhases(_ t: Double) -> (CGFloat, CGFloat) {
        func ease(_ v: Double) -> CGFloat { let c = CGFloat(min(max(v, 0), 1)); return c * c * (3 - 2 * c) }
        return (ease(t / (climbTime / 2)), ease((t - climbTime / 2) / (climbTime / 2)))
    }
    /// How far (pose-local) the window's top edge is above the cat's feet anchor at time `t` of the climb.
    static func climbEdge(_ t: Double) -> CGFloat {
        let (a, b) = climbPhases(t)
        return hangEdge * (1 - 0.55 * a) * (1 - b)
    }

    var cs: CGFloat { catScale * coats[s.coat % coats.count].size * CGFloat(s.sizeMul) }   // on-screen scale for this breed + size setting
    var lowPower = false        // Battery Saver: skip purely decorative particles
    var watchdogTrips = 0       // times the watchdog had to rescue the cat (self-test reports this)
    var watchT = 0.0

    /// Frames per second this moment actually needs: calm poses barely change, so they're drawn far less often.
    var activityFPS: Double {
        switch act {
        case .sleep, .deepSleep, .hide, .loaf, .sit, .waitBowl, .face, .lookUp, .goTo, .goTreat, .hunt, .play: return 8
        case .groom, .eat, .scratch, .petted, .brushed, .meow, .yawn, .stretch, .archStretch, .legStretch, .bigArch,
             .annoyed, .strain, .dig, .alert, .eatTreat, .hairball, .claw, .swat: return 15
        default: return 30
        }
    }

    /// Whether window positions need checking every frame (riding a window, mid-jump, hanging off one).
    var needsLiveWindows: Bool {
        if case .window = surface { return true }
        if isAirborne { return true }
        switch act { case .claw, .crawl, .hide: return true; default: return false }
    }

    /// Rescue the cat from any state it shouldn't be in (bad numbers, off screen, a stuck action).
    func watchdog() {
        let v = world.vis
        func rescue() { watchdogTrips += 1; surface = .floor; vx = 0; vy = 0; y = world.floorY; interrupt([.sit(1)]) }
        if !x.isFinite || !y.isFinite || !vx.isFinite || !vy.isFinite { x = v.midX; rescue(); return }
        let offOK: Bool = { switch act { case .exitTo, .dig, .strain, .walk, .carried: return true; default: return false } }()
        if !offOK && (x < v.minX - 60 || x > v.maxX + 60) { x = clampf(x, v.minX + 40, v.maxX - 40); rescue(); return }
        if case .carried = act {   // you're holding it — unless the mouse-up got lost (screen locked mid-drag…)
            if actT > 0.5 && NSEvent.pressedMouseButtons & 1 == 0 { watchdogTrips += 1; drop(velocity: .zero) }
            return
        }
        if y < world.floorY - 4 { y = world.floorY; if isAirborne { rescue() }; return }
        let limit: Double
        switch act {
        case .deepSleep: limit = 45 * 60
        case .sleep, .hide: limit = 20 * 60
        case .loaf: limit = 10 * 60
        case .leap, .hop, .leapCatch: limit = 8
        default: limit = 3 * 60
        }
        if actT > limit { rescue() }
    }

    /// Keep everything sensible after the display layout changes (monitor unplugged, resolution changed).
    func reclamp() {
        let v = world.vis
        switch act {
        case .exitTo, .dig, .strain: break
        default: x = clampf(x, v.minX + 24, v.maxX - 24)
        }
        if surface == .floor { y = world.floorY }
        if y > v.maxY - 70 { y = v.maxY - 70 }
    }

    init(world: World, state: SaveState, sound: SoundBox) {
        self.world = world; self.s = state; self.sound = sound
    }

    // MARK: state queries

    var isSleeping: Bool {
        switch act { case .sleep, .hide, .deepSleep: return true; default: return false }
    }
    var isHidden: Bool { if case .hide = act { return true }; return false }
    var isAirborne: Bool {
        switch act { case .leap, .hop, .carried, .leapCatch, .hang, .pullUp: return true; default: return false }
    }
    var isLongLoaf: Bool {
        if case .deepSleep = act { return true }
        return queue.contains { if case .deepSleep = $0 { return true }; return false }
    }
    var mood: String {
        if isSleeping { return "is fast asleep" }
        if s.hydration < 0.25 { return "is very thirsty" }
        if s.belly < 0.25 { return "is very hungry" }
        if s.hydration < 0.45 { return "is a little thirsty" }
        if s.belly < 0.45 { return "is a little hungry" }
        if s.energy < 0.3 { return "is sleepy" }
        if s.happiness < 0.35 { return "wants some attention" }
        if s.happiness > 0.8 { return "is purring contentedly" }
        return "is doing cat things"
    }

    /// Screen rects that should cover the cat: the window it's squeezing under, or windows
    /// stacked in front of the one it's sitting on. (macOS won't let us slot our window between
    /// another app's windows, so we erase the hidden parts instead.)
    func occluders() -> [CGRect] {
        if case .carried = act { return [] }
        let sc = world.screen
        var rs = [CGRect(x: sc.minX - 2000, y: sc.minY - 2000, width: 2000, height: sc.height + 4000),
                  CGRect(x: sc.maxX, y: sc.minY - 2000, width: 2000, height: sc.height + 4000)]
        var behind: CGWindowID? = nil
        switch act {
        case .crawl(_, let id), .hide(let id, _): behind = id
        case .leap, .hop, .leapCatch, .hang, .pullUp: return rs
        default: if case .window(let id) = surface { behind = id }
        }
        guard let id = behind, let p = world.plat(id) else { return rs }
        rs += world.all.filter { $0.order < p.order }.map(\.rect)
        if surface == .floor { rs.append(p.rect) }
        return rs
    }

    func hitRect() -> CGRect {
        let top = (pose.headC.y + pose.headR * 1.9) * cs
        return CGRect(x: x - 36, y: y - 4, width: 72, height: top + 6)
    }

    func range() -> (CGFloat, CGFloat) {
        let v = world.vis
        if case .window = surface {
            let lo = max(surfRect.minX, v.minX) + 24, hi = min(surfRect.maxX, v.maxX) - 24
            return hi > lo ? (lo, hi) : (x, x)
        }
        return (v.minX + 30, v.maxX - 30)
    }

    func heart() {
        let hx = x + facing * (pose.headC.x + 4) * cs, hy = y + (pose.headC.y + pose.headR * 1.6) * cs
        hearts.append((P(hx + rnd(-8, 8), hy + rnd(0, 6)), 0, rndD(0, 6)))
    }

    func startle() { startleUntil = time + 0.9 }
    func meow() { lastMeowAt = time; sound.meow() }

    // MARK: tick

    func tick(_ dt: Double) {
        time += dt; actT += dt
        watchT += dt
        if watchT > 1 { watchT = 0; watchdog() }
        let m = NSEvent.mouseLocation
        updateNeeds(dt)
        hearts = hearts.compactMap { h in
            h.age > 1.5 ? nil : (h.p.off(CGFloat(cos((h.age + h.sway) * 5)) * 0.5, CGFloat(dt) * 24), h.age + dt, h.sway)
        }
        if case .petted = act, Int(actT / 0.7) != Int((actT - dt) / 0.7) { heart() }
        fur = fur.compactMap { f in
            guard f.age < 3 else { return nil }
            var p = f.p
            if p.y > world.floorY { p = p.off(f.v.x * CGFloat(dt) + CGFloat(sin((f.age + Double(p.x)) * 4)) * 0.4, -f.v.y * CGFloat(dt)) }
            p.y = max(p.y, world.floorY)
            return (p, f.v, f.age + dt)
        }
        if trait == .skittish, time - lastScare > 20, !isSleeping, !isAirborne, !isHidden {
            let d = hypot(m.x - mouse.x, m.y - mouse.y)
            if d / CGFloat(max(dt, 0.001)) > 1600 && abs(m.x - x) < 140 && abs(m.y - (y + 30)) < 120 {
                lastScare = time; startle()
                let dir: CGFloat = x >= m.x ? 1 : -1
                interrupt([.hop(dir * rnd(220, 280), 520)] + (chance(0.5) ? planHide() : [.face(-dir), .alert(1.5)]))
            }
        }
        litter = litter.compactMap { l in
            guard l.age < 2.6 else { return nil }
            var p = l.p, v = l.v
            if p.y > world.floorY || v.y > 0 {
                v.y -= 900 * CGFloat(dt); p = p.off(v.x * CGFloat(dt), v.y * CGFloat(dt))
                if p.y <= world.floorY { p.y = world.floorY; v = .zero }
            }
            return (p, v, l.age + dt)
        }
        if hypot(m.x - mouse.x, m.y - mouse.y) > 2 { lastMouseMove = time; mouse = m }
        if time > nextBlink { blinkUntil = time + 0.14; nextBlink = time + rndD(2.5, 6) }

        switch act {
        case .sit, .lookUp:
            if time - lastMouseMove < 1.2, abs(mouse.x - x) < 450, abs(mouse.x - x) > 10 {
                facing = mouse.x > x ? 1 : -1   // cats watch the cursor
            }
        default: break
        }
        run(dt)
        pose = makePose()
    }

    func updateNeeds(_ dt: Double) {
        s.coatCare = clampd(s.coatCare - dt / ((fluffy ? 6 : 10) * 3600), 0, 1)
        s.belly = clampd(s.belly - dt / (3 * 3600), 0, 1)
        s.hydration = clampd(s.hydration - dt / (2.5 * 3600), 0, 1)
        s.energy = clampd(s.energy + (isSleeping ? dt / 360 : -dt / (2 * 3600)), 0, 1)
        let rate = (s.belly < 0.2 || s.hydration < 0.2) ? 3.0 : 1.0
        s.happiness = clampd(s.happiness - dt * rate / (4 * 3600), 0, 1)
    }

    /// Called every frame after the window list refreshes: ride along with (or fall off) our window.
    /// Returns true if the window under the cat moved (so the app can draw smoothly while you drag it).
    @discardableResult
    func poll() -> Bool {
        guard case .window(let id) = surface else { return false }
        guard let p = world.plat(id), p.top + 50 < world.vis.maxY + 30 else { fall(); return true }
        var moved = false
        if p.rect != surfRect {
            x += p.rect.minX - surfRect.minX
            y = p.top
            surfRect = p.rect
            moved = true
        }
        if x < p.rect.minX - 4 || x > p.rect.maxX + 4 { fall() }
        return moved
    }

    func fall() { startle(); interrupt([.hop(0, 80)]) }

    // MARK: action machine

    func next() {
        if queue.isEmpty { decide() }
        act = queue.removeFirst(); actT = 0
        begin()
    }

    func interrupt(_ acts: [Act]) { queue = acts; next() }

    func begin() {
        switch act {
        case .walk(let tx, let sp):
            let r = range()
            let t = clampf(tx, r.0, r.1)
            act = .walk(t, trait == .lazy && sp < 200 ? sp * 0.8 : sp)
            if abs(t - x) > 1 { facing = t > x ? 1 : -1 }
        case .crawl(let tx, _):
            facing = tx > x ? 1 : -1
        case .face(let d):
            facing = d
        case .goTo(let id):
            guard let p = world.stand.first(where: { $0.id == id }) else { act = .sit(1); return }
            queue = jumpTo(p) + queue
            act = .face(facing)
        case .leapOn(let id, let off):
            guard let p = world.plat(id), world.stand.contains(where: { $0.id == id }) else {
                act = .sit(1); tiltUntil = time + 1.2; return   // window's gone — puzzled head tilt
            }
            let dy = p.top - y
            if dy > 120 && (forceCatch || chance(0.05) || (dy > maxJumpUp * 0.85 && chance(0.15))) {   // rarely: not quite enough oomph
                forceCatch = false
                act = .leapCatch(id, off); begin(); return
            }
            act = .leap(P(clampf(p.rect.minX + off, p.rect.minX + 30, p.rect.maxX - 30), p.top)); begin()
        case .leapCatch(let id, let off):
            guard let p = world.plat(id) else { act = .sit(1); return }
            let tx = clampf(p.rect.minX + off, p.rect.minX + 30, p.rect.maxX - 30)
            let ty = p.top - Cat.hangEdge * cs
            vy = sqrt(2 * gravity * max(10, ty - y))
            let T = vy / gravity
            vx = (tx - x) / T
            if abs(tx - x) > 2 { facing = tx > x ? 1 : -1 }
            takeoff()
            catchAt = time + Double(T)
        case .leap(let tg):
            let dx = tg.x - x, dy = tg.y - y
            let T: CGFloat = dy > 10 ? sqrt(2 * dy / gravity) * 1.22 + 0.18 : (dy < -10 ? sqrt(2 * -dy / gravity) * 0.85 + 0.25 : 0.5)
            vx = dx / T; vy = (dy + 0.5 * gravity * T * T) / T
            if abs(dx) > 2 { facing = dx > 0 ? 1 : -1 }
            takeoff()
        case .hop(let hvx, let hvy):
            vx = hvx; vy = hvy
            takeoff()
        case .eat:
            if surface != .floor { queue = []; act = .sit(0.5) } else { facing = 1 }
        case .waitBowl:
            facing = 1; lastWait = time
        case .meow, .lookUp:
            meow()
        case .play(let n):
            act = .face(facing)
            queue = planPlay(n) + queue
        case .pounceToy:
            guard let t = toy else { act = .sit(0.5); return }
            act = .leap(P(t.x - facing * 14, t.y)); begin()
        case .bat, .scoop:
            if let t = toy, abs(t.x - x) > 2 { facing = t.x > x ? 1 : -1 }
        case .bunnyKick:
            guard let t = toy, !t.held, abs(t.x - x) < 70, t.surface == surface else { act = .bat; begin(); return }
            facing = t.x >= x ? 1 : -1
            t.held = true; t.vx = 0; t.vy = 0
        case .hunt(let n):
            act = .face(facing)
            queue = planHunt(n) + queue
        case .stalk:
            if let m = critter { facing = m.x > x ? 1 : -1 }
        case .pounceMouse:
            guard let m = critter else { act = .sit(0.5); return }
            act = .leap(P(m.x + m.dir * m.speed * 0.4, world.floorY)); begin()
        case .goTreat:
            act = .face(facing)
            queue = planTreat() + queue
        case .eatTreat:
            guard let t = treat, abs(t.x - x) < 70 else { act = .sit(0.5); return }
            facing = t.x >= x ? 1 : -1
        case .exitTo(let tx):
            if abs(tx - x) > 1 { facing = tx > x ? 1 : -1 }
        default: break
        }
    }

    func takeoff() {
        if case .window(let id) = surface { ignoreID = id; ignoreUntil = time + 0.3 } else { ignoreID = 0 }
        surface = .air
    }

    func run(_ dt: Double) {
        var done = false
        switch act {
        case .sit(let d), .loaf(let d), .groom(let d), .scratch(let d), .annoyed(let d), .petted(let d), .lookUp(let d):
            done = actT >= d
            if done, case .loaf = act, chance(0.3) { queue.insert(.archStretch, at: 0) }
        case .sleep(let d):
            done = actT >= d || (s.energy >= 0.99 && actT > 40)
            if done { queue.insert(contentsOf: wakeStretches(), at: 0) }
        case .hide(let id, let d):
            done = actT >= d
            let p = world.plat(id)
            if p == nil || !(p!.rect.minY <= world.floorY + 42 && p!.rect.minX < x - 20 && p!.rect.maxX > x + 20) {
                queue = [.sit(1.5)]; startle(); done = true    // someone moved the window — discovered!
            }
        case .stretch: done = actT >= 2.6
        case .archStretch: done = actT >= 2.4
        case .bigArch: done = actT >= 3.2
        case .legStretch: done = actT >= 2.0
        case .yawn: done = actT >= 1.6
        case .meow: done = actT >= 1.4
        case .swat: done = actT >= 0.6
        case .alert(let d): done = actT >= d
        case .brushed(let d): done = actT >= d
        case .claw(let id, let edge, let d):
            guard let p = world.plat(id), abs(p.rect.minX - edge) < 12 || abs(p.rect.maxX - edge) < 12 else {
                startle(); done = true; break   // the "post" moved away
            }
            done = actT >= d
        case .hairball(let d):
            if actT >= d {
                done = true
                hairballOut = true
                onHairball?(P(x + facing * 30 * cs, y), surface, surfRect)
                queue = [.sit(rndD(1, 2)), .groom(rndD(2, 4))]   // as if nothing happened
            }
        case .leapCatch(let id, let off):
            let d = CGFloat(dt)
            vy -= gravity * d; x += vx * d; y += vy * d
            if abs(vx) > 5 { facing = vx > 0 ? 1 : -1 }
            if time >= catchAt {
                if let p = world.plat(id) {   // paws hook over the edge
                    x = clampf(p.rect.minX + off, p.rect.minX + 30, p.rect.maxX - 30)
                    y = p.top - Cat.hangEdge * cs
                    surfRect = p.rect; vx = 0; vy = 0
                    if s.collarOn { sound.jingle() }
                    act = .hang(id, rndD(1.3, 2.4)); actT = 0
                } else {
                    act = .hop(vx * 0.3, 0); actT = 0
                }
            }
        case .hang(let id, let d):
            guard let p = world.plat(id) else { act = .hop(0, 0); actT = 0; break }
            x += p.rect.minX - surfRect.minX; surfRect = p.rect
            y = p.top - Cat.hangEdge * cs
            if actT >= d {
                if forceGrip || chance(0.8) { act = .pullUp(id); actT = 0 }
                else { queue = [.sit(1.2), .groom(rndD(2, 3))]; act = .hop(0, 0); actT = 0; begin() }   // lost the grip
            }
        case .pullUp(let id):
            guard let p = world.plat(id) else { act = .hop(0, 0); actT = 0; break }
            x += p.rect.minX - surfRect.minX; surfRect = p.rect
            y = p.top - Cat.climbEdge(actT) * cs   // paws stay on the edge; the body does the moving
            if actT >= Cat.climbTime { y = p.top; settle(.window(id), p.rect); done = true }
        case .face, .goTo: done = true
        case .crouch(let d): done = actT >= d
        case .land: done = actT >= 0.22
        case .walk(let tx, let sp):
            let r = range()
            let t = clampf(tx, r.0, r.1)
            let step = sp * CGFloat(dt)
            phase += CGFloat(dt) * sp / 8.5
            if abs(t - x) <= step { x = t; done = true } else { x += t > x ? step : -step; facing = t > x ? 1 : -1 }
        case .crawl(let tx, _):
            let step = 42 * CGFloat(dt)
            phase += CGFloat(dt) * 42 / 6
            if abs(tx - x) <= step { x = tx; done = true } else { x += tx > x ? step : -step }
        case .leap, .hop:
            done = physics(dt)
        case .leapOn, .play, .pounceToy:
            done = true
        case .chase(let maxT):
            guard let t = toy, t.surface == surface || t.surface == .air else { done = true; break }
            let r = range()
            let goal = clampf(t.x - (t.x >= x ? 1 : -1) * 34, r.0, r.1)
            let step = 230 * CGFloat(dt)
            phase += CGFloat(dt) * 230 / 8.5
            if abs(goal - x) <= step { x = goal; done = true } else { x += goal > x ? step : -step; facing = goal > x ? 1 : -1 }
            if actT > maxT { done = true }
        case .bat, .scoop:
            if actT >= 0.15 && actT - dt < 0.15, let t = toy, !t.held,
               abs(t.x - (x + facing * 22)) < 42, abs(t.y - y) < 30 {
                if case .scoop = act { t.kick(facing * rnd(30, 90), rnd(480, 620)); played() }
                else { kickToy(t, strong: false) }
            }
            done = actT >= 0.45
        case .bunnyKick(let d):
            if let t = toy {   // hug the yarn against the belly while the back feet pummel it
                t.x = x + facing * 15 * cs; t.y = y + 19 * cs
                t.surface = surface; t.surfRect = surfRect; t.spin += CGFloat(dt) * 8
            }
            if actT >= d { done = true; if let t = toy { t.held = false; kickToy(t, strong: true) } }
        case .hunt, .goTreat, .pounceMouse:
            done = true
        case .stalk(let maxT):
            guard let m = critter, !m.fleeing else { done = true; break }
            facing = m.x > x ? 1 : -1
            let sp: CGFloat = abs(m.x - x) > 480 ? 100 : 50   // low trot from afar, then a belly-down crawl
            phase += CGFloat(dt) * sp / (sp > 60 ? 8.5 : 6)
            x += facing * sp * CGFloat(dt)
            done = abs(m.x - x) < 210 || actT > maxT
        case .chaseMouse(let maxT):
            guard let m = critter else { done = true; break }
            let r = range()
            let goal = clampf(m.x, r.0, r.1)
            let step = 270 * CGFloat(dt)
            phase += CGFloat(dt) * 270 / 8.5
            if abs(goal - x) <= step { x = goal; done = true } else { x += goal > x ? step : -step; facing = goal > x ? 1 : -1 }
            if actT > maxT { done = true }
        case .eatTreat:
            if actT >= 2.0 {
                done = true
                treat?.gone = true
                s.happiness = min(1, s.happiness + 0.15); s.belly = min(1, s.belly + 0.04)
                for _ in 0..<3 { heart() }
                sound.doPurr()
            }
        case .exitTo(let tx):
            let step = 75 * CGFloat(dt)
            phase += CGFloat(dt) * 75 / 8.5
            if abs(tx - x) <= step { x = tx; done = true } else { x += tx > x ? step : -step }
        case .dig(let d):
            if Int(actT / 0.09) != Int((actT - dt) / 0.09) {   // fling litter back onto the screen
                let fx = x - facing * 36 * cs
                for _ in 0..<(lowPower ? 0 : Int.random(in: 1...2)) {
                    litter.append((P(fx, y + 4), P(-facing * rnd(40, 130), rnd(150, 300)), 0))
                }
            }
            done = actT >= d
        case .strain(let d):
            shake = Int(actT * 14) % 2 == 0 ? 1 : -1
            done = actT >= d
            if done { shake = 0 }
        case .deepSleep(let d):
            done = actT >= d
            if done { queue.insert(contentsOf: wakeStretches(), at: 0) }
        case .eat(let w):
            if w {
                s.water = max(0, s.water - 0.045 * dt); s.hydration = min(1, s.hydration + 0.11 * dt)
                done = s.water <= 0 || s.hydration >= 0.99 || actT > 9
            } else {
                s.food = max(0, s.food - 0.035 * dt); s.belly = min(1, s.belly + 0.09 * dt)
                done = s.food <= 0 || s.belly >= 0.99 || actT > 10
            }
            if done {
                s.happiness = min(1, s.happiness + 0.05)
                if (w ? s.water : s.food) <= 0.01 { queue.insert(.waitBowl(w), at: 0) }
                queue.append(.groom(rndD(3, 6)))   // cats always wash up after a meal
                if !w && s.litterOn && time - lastLitter > 20 * 60 && chance(0.06) { queue += planLitter() }
            }
        case .waitBowl(let w):
            if (w ? s.water : s.food) > 0.04 { act = .eat(w); actT = 0; begin(); return }
            if Int(actT / 4) != Int((actT - dt) / 4) { meow() }
            done = actT >= 25
        case .carried:
            break
        }
        if done { next() }
    }

    func physics(_ dt: Double) -> Bool {
        let d = CGFloat(dt), py = y
        vy -= gravity * d; x += vx * d; y += vy * d
        let v = world.vis
        if x < v.minX + 24 { x = v.minX + 24; vx = abs(vx) * 0.3 }
        if x > v.maxX - 24 { x = v.maxX - 24; vx = -abs(vx) * 0.3 }
        if y > v.maxY - 70 { y = v.maxY - 70; vy = min(vy, 0) }
        if abs(vx) > 5 { facing = vx > 0 ? 1 : -1 }
        guard vy <= 0 else { return false }
        var best: Plat? = nil
        for p in world.stand {
            if p.id == ignoreID && time < ignoreUntil { continue }
            if py >= p.top - 1 && y <= p.top && x > p.rect.minX + 10 && x < p.rect.maxX - 10 && world.topVisible(p, x) {
                if best == nil || p.top > best!.top { best = p }
            }
        }
        if let p = best { y = p.top; settle(.window(p.id), p.rect); return true }
        if y <= world.floorY { y = world.floorY; settle(.floor, .zero); return true }
        return false
    }

    func settle(_ sf: Surface, _ r: CGRect) {
        surface = sf; surfRect = r; vx = 0; vy = 0
        if s.collarOn { sound.jingle() }
        queue.insert(.land, at: 0)
    }
}
