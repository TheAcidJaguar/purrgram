// DesktopCat — a headless self-test that build.sh runs on every build.

import Cocoa

// MARK: - Self-test

/// Headless self-test (build.sh runs it on every build): renders every pose for every breed, then simulates each
/// behavior — plus a long free-running session — checking the cat never goes somewhere impossible or gets stuck.
func selfTest() -> Int32 {
    var fails: [String] = []
    let world = World()
    world.screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    world.vis = CGRect(x: 0, y: 0, width: 1440, height: 875)
    world.bowlRect = CGRect(x: 1290, y: 0, width: BowlView.size.width, height: BowlView.size.height)
    let shelf = Plat(id: 1, rect: CGRect(x: 380, y: 200, width: 420, height: 300), order: 0)   // a window to jump onto
    let low = Plat(id: 2, rect: CGRect(x: 900, y: 10, width: 330, height: 260), order: 1)      // one down at the floor
    world.all = [shelf, low]; world.stand = [shelf, low]

    func newCat() -> Cat {
        var st = SaveState(); st.sound = false; st.personality = Personality.curious.rawValue
        let snd = SoundBox(); snd.enabled = { false }
        let c = Cat(world: world, state: st, sound: snd)
        c.x = 200; c.y = 0; c.act = .sit(1)
        return c
    }
    func name(_ a: Act) -> String { String(String(describing: a).prefix { $0 != "(" }) }

    // 1. Every pose renders, for every breed, facing both ways.
    let poseActs: [Act] = [.sit(9), .loaf(9), .sleep(9), .groom(9), .scratch(9), .stretch, .archStretch, .legStretch, .yawn,
                           .bigArch, .meow, .annoyed(9), .swat, .petted(9), .lookUp(9), .walk(9e9, 70), .walk(9e9, 300),
                           .crawl(9e9, 1), .crouch(9), .leap(.zero), .land, .hide(1, 9), .eat(false), .eat(true),
                           .waitBowl(false), .carried, .bat, .scoop, .bunnyKick(9), .stalk(9), .chaseMouse(9), .eatTreat,
                           .dig(9), .strain(9), .deepSleep(9), .alert(9), .hang(1, 9), .pullUp(1), .brushed(9),
                           .hairball(9), .claw(1, 380, 9)]
    let rc = newCat()
    var renders = 0
    for (ci, coat) in coats.enumerated() {
        for a in poseActs {
            for t in [0.0, 0.7, 1.9] {
                rc.act = a; rc.actT = t; rc.time = t
                if Painter.image(rc.makePose(), coat: coat, facing: ci % 2 == 0 ? 1 : -1, size: CGSize(width: VW, height: VH),
                                 origin: P(OX, OY), collar: rgb(0xC8323C)) == nil { fails.append("render failed: \(coat.name) \(name(a))") }
                renders += 1
            }
        }
    }

    // 2. Behaviors, simulated at 30 fps.
    var scenarios = 0
    func run(_ label: String, seconds: Double, setup: (Cat) -> Void) {
        scenarios += 1
        let c = newCat(); setup(c)
        let dt = 1.0 / 30
        var seen = Set([name(c.act)])
        var t = 0.0
        while t < seconds {
            c.poll(); c.tick(dt)
            c.toy?.tick(dt); c.treat?.tick(dt)
            if let m = c.critter { m.tick(dt, cat: c); if m.gone { c.critter = nil } }
            if c.toy?.gone == true { c.toy = nil }
            if c.treat?.gone == true { c.treat = nil }
            t += dt
            seen.insert(name(c.act))
            let v = world.vis
            let offOK: Bool = { switch c.act { case .exitTo, .dig, .strain, .walk: return true; default: return false } }()
            if !c.x.isFinite || !c.y.isFinite { fails.append("\(label): position became invalid"); return }
            if !offOK && (c.x < v.minX - 60 || c.x > v.maxX + 60) { fails.append("\(label): left the screen (x=\(Int(c.x)))"); return }
            if c.y < world.floorY - 4 || c.y > v.maxY { fails.append("\(label): out of bounds (y=\(Int(c.y)))"); return }
        }
        if seen.count < 2 { fails.append("\(label): stuck in \(seen.first ?? "?")") }
        if c.watchdogTrips > 0 { fails.append("\(label): watchdog had to rescue the cat \(c.watchdogTrips)×") }
    }
    run("wander", seconds: 30) { $0.queue = $0.wander() }
    run("jump onto a window", seconds: 30) { $0.queue = $0.jumpTo(shelf) }
    run("edge catch", seconds: 30) { $0.forceCatch = true; $0.queue = $0.jumpTo(shelf) }
    run("jump down", seconds: 30) { c in c.x = 500; c.y = 500; c.surface = .window(1); c.surfRect = shelf.rect; c.queue = c.goToFloor() }
    run("hide under a window", seconds: 120) { $0.queue = $0.planHide() }
    run("nap", seconds: 400) { c in c.s.energy = 0.1; c.queue = [.sleep(200)] }
    run("zoomies", seconds: 30) { $0.queue = $0.planZoomies() }
    run("litter box", seconds: 60) { $0.queue = $0.planLitter() }
    run("scratch a window edge", seconds: 30) { $0.queue = $0.planClaw() }
    run("eat", seconds: 40) { c in c.s.food = 1; c.queue = c.planBowl(false) }
    run("drink", seconds: 40) { c in c.s.water = 1; c.queue = c.planBowl(true) }
    run("empty bowl", seconds: 40) { c in c.s.food = 0; c.queue = c.planBowl(false) }
    run("treat", seconds: 30) { c in c.treat = Toy(world: world, kind: .treat, x: 600, y: 300); c.queue = [.goTreat] }
    run("yarn", seconds: 120) { c in c.toy = Toy(world: world, kind: .yarn, x: 400, y: 300); c.queue = [.play(0)] }
    run("mouse", seconds: 40) { c in c.critter = Critter(world: world, fromLeft: false); c.queue = [.alert(1), .hunt(0)] }
    run("hairball", seconds: 20) { $0.queue = [.hairball(3)] }
    run("big arch", seconds: 15) { $0.queue = [.bigArch] }
    run("loaf for 30 minutes", seconds: 200) { $0.loafHere() }
    run("picked up and dropped", seconds: 10) { c in c.startCarry(); c.carry(to: P(700, 600)); c.drop(velocity: P(300, 100)) }
    run("a free-running hour", seconds: 3600) { _ in }

    if fails.isEmpty {
        print("✓ self-test passed: \(renders) renders, \(scenarios) behaviors")
        return 0
    }
    print("✗ self-test failed:"); fails.forEach { print("   - \($0)") }
    return 1
}
