// DesktopCat — the app: windows, frame loop, system events and the menu bar menu.

import Cocoa
import ServiceManagement

// MARK: - Menu bar icon

/// A pixel cat face for the menu bar, drawn as a template image so it tints with the menu bar.
enum MenuIcon {
    static let face = [
        ".##..........##.",
        ".###........###.",
        ".####......####.",
        ".##############.",
        "################",
        "################",
        "####..####..####",
        "####..####..####",
        "################",
        "#######..#######",
        "################",
        ".##############.",
        "..############..",
        "....########....",
    ]

    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            for (r, row) in face.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    NSRect(x: CGFloat(c), y: CGFloat(face.count - r), width: 1, height: 1).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Purrgram"
        return img
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let world = World()
    let sound = SoundBox()
    var cat: Cat!
    var catWin: NSWindow!, catView: CatView!
    var bowlWin: NSWindow!, bowlView: BowlView!
    var toy: Toy?, toyWin: NSWindow?, toyView: ToyView?
    var treat: Toy?, treatWin: NSWindow?, treatView: ToyView?
    var critter: Critter?, critterWin: NSWindow?, critterView: CritterView?
    var hairball: Toy?, hairballWin: NSWindow?, hairballView: ToyView?
    var lastStroke = 0.0
    var allHidden = false
    var nextMouseAt = CACurrentMediaTime() + rndD(8 * 60, 20 * 60)   // a mouse wanders in every so often
    var status: NSStatusItem!
    var timer: Timer?
    var fps = 30.0
    var lastRefresh = 0.0, boostUntil = 0.0
    var pauseReasons = Set<String>()                 // display asleep, Mac asleep, screen locked, screensaver…
    var paused: Bool { !pauseReasons.isEmpty }
    var batterySaver = false                         // follows macOS Low Power Mode
    var awaySince: Date?, vacationAway: TimeInterval = 0, vacationNoteUntil = Date.distantPast
    var settings: SettingsController?
    var mouseMonitor: Any?
    var termSource: DispatchSourceSignal?
    var pendingSave: DispatchWorkItem?
    var last = CACurrentMediaTime()
    var saveAcc = 0.0, frontAcc = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        world.refresh()
        cat = Cat(world: world, state: Store.load(), sound: sound)
        if cat.s.personality < 0 { cat.s.personality = Personality.allCases.randomElement()!.rawValue; Store.save(cat.s) }
        cat.onHairball = { [weak self] p, sf, r in self?.dropHairball(at: p, surface: sf, rect: r) }
        sound.enabled = { [weak self] in self?.cat.s.sound ?? true }
        // Stroll in from the left edge of the screen rather than popping into existence.
        cat.x = world.vis.minX - 40; cat.y = world.floorY; cat.facing = 1
        cat.act = .walk(world.vis.minX + rnd(160, 420), 70); cat.queue = [.sit(2)]

        bowlWin = makeWindow(world.bowlRect)
        bowlView = BowlView(frame: NSRect(origin: .zero, size: world.bowlRect.size))
        bowlView.cat = cat; bowlView.shownFood = cat.s.food; bowlView.shownWater = cat.s.water
        bowlWin.contentView = bowlView
        bowlWin.orderFrontRegardless()

        catWin = makeWindow(NSRect(x: cat.x - OX, y: cat.y - OY, width: VW, height: VH))
        catView = CatView(frame: NSRect(x: 0, y: 0, width: VW, height: VH))
        catView.cat = cat; catView.bowlView = bowlView
        catWin.contentView = catView
        catWin.orderFrontRegardless()

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = MenuIcon.image()
        status.button?.imagePosition = .imageOnly
        let menu = NSMenu(); menu.delegate = self; status.menu = menu

        updatePower()
        setFPS(30)
        observeSystem()
        // Keep click-through hit testing instant even when the cat is drawn at a low frame rate.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateHits()
            self?.mouseMovedWhilePaused()
        }
        // `kill`/`pkill` (SIGTERM) skips applicationWillTerminate — save on the way out anyway.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in if let s = self?.cat?.s { Store.save(s) }; exit(0) }
        term.resume(); termSource = term

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        if let dbg = ProcessInfo.processInfo.environment["DESKTOPCAT_DEBUG"] { setupDebug(dbg) }
        if !cat.s.named {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.askName(first: true) }
        }
    }

    /// Developer hook: `DESKTOPCAT_DEBUG=/path/log.txt` logs state there, and posting the distributed
    /// notification "com.desktopcat.debug" with a command string triggers that behavior.
    func setupDebug(_ path: String) {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.desktopcat.debug"), object: nil, queue: .main) { [weak self] n in
            guard let cat = self?.cat, let cmd = n.object as? String else { return }
            let plans: [String: () -> [Act]] = ["jump": cat.planJumpUp, "hide": cat.planHide, "sleep": cat.planSleep,
                                                "eat": { cat.planBowl(false) }, "drink": { cat.planBowl(true) },
                                                "zoom": cat.planZoomies, "pounce": cat.planPounce, "floor": cat.goToFloor,
                                                "groom": { [.groom(6)] }, "scratch": { [.scratch(3)] },
                                                "stretch": { [.stretch, .legStretch, .archStretch, .yawn] }]
            if cmd == "pet" { cat.pet(); return }
            if cmd == "settings" { self?.openSettings(); return }
            if cmd == "settings-close" { self?.settings?.window.orderOut(nil); return }
            if cmd == "yarn" { self?.toggleYarn(); return }
            if cmd == "treat" { self?.giveTreat(); return }
            if cmd == "mouse" { self?.releaseMouse(); return }
            if cmd == "loaf" { self?.toggleLoaf(); return }
            if cmd == "litter" { cat.interrupt(cat.planLitter()); return }
            if cmd == "brush" { self?.toggleBrush(); return }
            if cmd == "claw" { let c = cat.planClaw(); cat.interrupt(c.isEmpty ? [.lookUp(1)] : c); return }
            if cmd == "hide" { self?.toggleHidden(); return }
            if cmd == "vacation" {   // simulate 6 minutes with the display off, through the real pause/resume path
                self?.pause("display", away: true); self?.awaySince = Date().addingTimeInterval(-6 * 60)
                self?.resume("display"); return
            }
            if cmd == "arch" { cat.interrupt([.bigArch, .sit(2)]); return }
            if cmd == "stroke" { cat.brushStroke(at: P(cat.x, cat.y + 30)); return }
            if cmd == "hairball" { cat.interrupt([.hairball(3)]); return }
            if cmd == "catch" { cat.forceCatch = true; let j = cat.jumpToAny(); cat.interrupt(j.isEmpty ? [.lookUp(1)] : j); return }
            if let f = plans[cmd] { let p = f(); cat.interrupt(p.isEmpty ? [.lookUp(1)] : p) }
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let c = self?.cat, let w = self?.world else { return }
            let line = "t=\(String(format: "%.1f", c.time)) act=\(c.act) x=\(Int(c.x)) y=\(Int(c.y)) surf=\(c.surface) floor=\(Int(w.floorY)) stand=\(w.stand.map { "\($0.id)@\(Int($0.top))" }) occl=\(c.occluders().count) belly=\(String(format: "%.2f", c.s.belly)) food=\(String(format: "%.2f", c.s.food)) energy=\(String(format: "%.2f", c.s.energy)) toy=\(c.toy.map { "\(Int($0.x)),\(Int($0.y)) \($0.surface)" } ?? "none") mouse=\(c.critter.map { "\(Int($0.x)) \($0.mode)" } ?? "none") paused=\(self?.pauseReasons.sorted() ?? []) vac=\(Date() < (self?.vacationNoteUntil ?? .distantPast) ? Int(self?.vacationAway ?? 0) : 0)\n"
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
            else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
        }
    }

    func applicationWillTerminate(_ n: Notification) { Store.save(cat.s) }

    func makeWindow(_ r: NSRect) -> NSWindow {
        let w = NSWindow(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        return w
    }

    // MARK: frame loop

    /// Run the frame loop at `f` frames per second (re-created only when the rate actually changes).
    func setFPS(_ f: Double) {
        if timer != nil && f == fps { return }
        fps = f
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / f, repeats: true) { [weak self] _ in self?.frame() }
        t.tolerance = 0.25 / f   // let macOS batch wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    var props: [Toy] { [toy, treat, hairball].compactMap { $0 } }

    func frame() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.1); last = now
        if allHidden || paused { return }   // tucked away, or nobody can see the screen
        // Window positions: every frame only while something is riding/jumping/landing, otherwise a few times a second.
        let live = cat.needsLiveWindows || props.contains { $0.surface != .floor || $0.vx != 0 }
        if let tv = toyView, tv.dragging, NSEvent.pressedMouseButtons & 1 == 0 {   // the mouse-up never arrived
            tv.dragging = false; toy?.held = false
        }
        if live || now - lastRefresh > (batterySaver ? 1.0 : 0.4) { world.refresh(); lastRefresh = now }
        if bowlWin.frame != world.bowlRect { bowlWin.setFrame(world.bowlRect, display: true) }
        if cat.poll() { boostUntil = now + 1 }   // you're dragging its window — keep it smooth
        cat.tick(dt)
        bowlView.tick(dt)
        toy?.tick(dt); treat?.tick(dt)
        if let c = critter { c.tick(dt, cat: cat) }
        if toy?.gone == true { removeYarn() }
        if treat?.gone == true { removeTreat() }
        if critter?.gone == true { removeMouse() }
        hairball?.tick(dt)
        if hairball?.gone == true { removeHairball() }
        if cat.brushMode {   // brushing ends on its own after a quiet minute
            if cat.strokes > 0 { lastStroke = now; cat.strokes = 0 }
            if now - lastStroke > 60 { cat.brushMode = false }
        }
        if now > nextMouseAt {
            nextMouseAt = now + rndD(8 * 60, 20 * 60)
            if critter == nil && cat.s.miceOn { releaseMouse() }
        }
        sync(dt)
        saveAcc += dt
        if saveAcc > 30 { saveAcc = 0; Store.save(cat.s) }

        // Pick the next frame rate: as low as what's on screen allows.
        var f = cat.activityFPS
        let busyProps = critter != nil || !bowlView.bits.isEmpty || props.contains { $0.held || $0.surface == .air || $0.vx != 0 }
            || abs(bowlView.shownFood - cat.s.food) > 0.01 || abs(bowlView.shownWater - cat.s.water) > 0.01
        if now < boostUntil || busyProps { f = 30 }
        if !cat.hearts.isEmpty || !cat.fur.isEmpty || !cat.litter.isEmpty { f = max(f, 15) }
        if batterySaver { f = min(f, 12) }
        setFPS(f)
    }

    func sync(_ dt: Double) {
        let o = P((cat.x - OX).rounded() + cat.shake, (cat.y - OY).rounded())
        if catWin.frame.origin != o { catWin.setFrameOrigin(o) }
        if catView.dirty() { catView.needsDisplay = true }
        frontAcc += dt
        if frontAcc > 2 { frontAcc = 0; restack() }
        for (t, w, v) in [(toy, toyWin, toyView), (treat, treatWin, treatView), (hairball, hairballWin, hairballView)] {
            guard let t, let w, let v else { continue }
            let to = P((t.x - ToyView.size.width / 2).rounded(), (t.y - PX).rounded())
            if w.frame.origin != to { w.setFrameOrigin(to) }
            v.refresh()
        }
        if let c = critter, let cw = critterWin, let cv = critterView {
            let to = P((c.x - CritterView.size.width / 2).rounded(), (c.y - PX).rounded())
            if cw.frame.origin != to { cw.setFrameOrigin(to) }
            cv.needsDisplay = true
        }
        updateHits()
    }

    /// The cat stays above its bowls and toys. (While it eats, CatView draws the bowl's front wall over its face.)
    func restack() { catWin.orderFrontRegardless() }

    /// Our windows only accept clicks right over the cat, a bowl, the yarn or a hairball; everywhere else clicks pass through.
    func updateHits() {
        guard catWin != nil, !allHidden else { return }
        let m = NSEvent.mouseLocation
        let carrying: Bool = { if case .carried = cat.act { return true }; return false }()
        let catHit = carrying || (!cat.isHidden && cat.hitRect().contains(m) && !cat.occluders().contains { $0.contains(m) })
        if catWin.ignoresMouseEvents == catHit { catWin.ignoresMouseEvents = !catHit }
        let lp = P(m.x - bowlWin.frame.minX, m.y - bowlWin.frame.minY)
        let bowlHit = bowlView.bowlHit(lp) != nil && !catHit
        if bowlWin.ignoresMouseEvents == bowlHit { bowlWin.ignoresMouseEvents = !bowlHit }
        if let t = toy, let tw = toyWin, let tv = toyView {
            let toyHit = t.held || (tv.hitRect().contains(m) && !catHit)
            if tw.ignoresMouseEvents == toyHit { tw.ignoresMouseEvents = !toyHit }
        }
        if let h = hairball, let hw = hairballWin {
            let hit = CGRect(x: h.x - 12, y: h.y - 2, width: 24, height: 18).contains(m) && !catHit
            if hw.ignoresMouseEvents == hit { hw.ignoresMouseEvents = !hit }
        }
    }

    // MARK: system events

    /// Pause when nobody can see the screen (display asleep, Mac asleep, locked, screensaver, switched user).
    /// The cat's bars only change while your Mac is awake and Purrgram is running.
    func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        let pairs: [(NSNotification.Name, NSNotification.Name, String, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "display", true),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "sleep", true),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
        ]
        for (off, on, reason, away) in pairs {
            ws.addObserver(forName: off, object: nil, queue: .main) { [weak self] _ in self?.pause(reason, away: away) }
            ws.addObserver(forName: on, object: nil, queue: .main) { [weak self] _ in self?.resume(reason) }
        }
        let dn = DistributedNotificationCenter.default()
        for (off, on, reason) in [("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "lock"),
                                  ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "saver")] {
            dn.addObserver(forName: Notification.Name(off), object: nil, queue: .main) { [weak self] _ in self?.pause(reason, away: false) }
            dn.addObserver(forName: Notification.Name(on), object: nil, queue: .main) { [weak self] _ in
                if reason == "lock" { self?.pauseReasons.remove("saver") }   // you can't unlock with the screensaver still up
                self?.resume(reason)
            }
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updatePower()
        }
    }

    func pause(_ reason: String, away: Bool) {
        let was = paused
        pauseReasons.insert(reason)
        if away && awaySince == nil { awaySince = Date() }   // lid closed / display off: maybe a vacation
        if !was { timer?.invalidate(); timer = nil; Store.save(cat.s) }
    }

    func resume(_ reason: String) {
        pauseReasons.remove(reason)
        guard !paused else { return }
        last = CACurrentMediaTime()
        world.refresh(); cat.reclamp()
        if !allHidden { setFPS(30) }
        if let a = awaySince {   // back after 5+ minutes with the lid closed: vacation mode kept everything paused
            awaySince = nil
            let away = Date().timeIntervalSince(a)
            if away >= 5 * 60 {
                vacationAway = away; vacationNoteUntil = Date().addingTimeInterval(20 * 60)
                cat.welcomeBack()
            }
        }
    }

    /// Safety net for a missed "screensaver stopped" / "display woke" notification: if the mouse is moving,
    /// the display is on and the screensaver is gone, so don't stay paused for those reasons.
    func mouseMovedWhilePaused() {
        guard paused, pauseReasons.isSubset(of: ["display", "saver"]) else { return }
        pauseReasons.remove("saver")
        resume("display")   // clears the last reason and restarts, including the vacation-mode check
    }

    /// Coalesce bursts of saves (dragging the color wheel or size slider) into one write.
    func saveSoon() {
        pendingSave?.cancel()
        let w = DispatchWorkItem { [weak self] in if let s = self?.cat?.s { Store.save(s) } }
        pendingSave = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    /// Keep an open Settings window in step with changes made from the menu.
    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            if let st = self?.settings, st.window.isVisible { st.load() }
        }
    }

    func updatePower() {
        batterySaver = ProcessInfo.processInfo.isLowPowerModeEnabled
        cat?.lowPower = batterySaver
    }

    /// Display layout changed (monitor plugged/unplugged, resolution): keep the cat and its things on screen.
    func screensChanged() {
        world.refresh()
        cat.reclamp()
        let v = world.vis
        for t in props {
            t.x = clampf(t.x, v.minX + 12, v.maxX - 12)
            if t.surface == .floor { t.y = world.floorY } else if t.y > v.maxY - 30 { t.y = v.maxY - 30; t.surface = .air }
        }
        critter?.y = world.floorY
    }

    // MARK: menu

    /// A stat row: label, ten segments colored green / yellow / red by how good the value is, and a percentage.
    /// Shown as a custom view so the menu doesn't grey the colors out.
    func statItem(_ label: String, _ v: Double) -> NSMenuItem {
        let v = clampd(v, 0, 1)
        let n = Int((v * 10).rounded())
        let color: NSColor = v >= 0.6 ? .systemGreen : (v >= 0.3 ? .systemYellow : .systemRed)
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let str = NSMutableAttributedString(string: label.padding(toLength: 11, withPad: " ", startingAt: 0),
                                            attributes: [.font: mono, .foregroundColor: NSColor.labelColor])
        str.append(NSAttributedString(string: String(repeating: "▰", count: n), attributes: [.font: mono, .foregroundColor: color]))
        str.append(NSAttributedString(string: String(repeating: "▱", count: 10 - n), attributes: [.font: mono, .foregroundColor: NSColor.tertiaryLabelColor]))
        str.append(NSAttributedString(string: String(format: " %3d%%", Int((v * 100).rounded())),
                                      attributes: [.font: mono, .foregroundColor: NSColor.secondaryLabelColor]))
        let field = NSTextField(labelWithAttributedString: str)
        field.frame.origin = NSPoint(x: 14, y: 2)
        field.sizeToFit()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: field.frame.width + 28, height: field.frame.height + 4))
        view.addSubview(field)
        let it = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        it.view = view
        return it
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = cat.s
        if allHidden {
            let it = add(menu, "Unhide \(s.name)", #selector(toggleHidden)); it.keyEquivalent = "h"
            menu.addItem(.separator())
            add(menu, "Quit Purrgram", #selector(quit))
            return
        }
        let head = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        head.attributedTitle = NSAttributedString(string: "\(s.name) \(cat.mood)", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(head)
        let tr = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        tr.attributedTitle = NSAttributedString(string: "Mood: \(cat.trait.name) · \(coats[s.coat % coats.count].name)",
                                                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(tr)
        func note(_ text: String) {
            let it = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            it.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11),
                                                                               .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(it)
        }
        if batterySaver { note("🔋 Battery Saver on (Low Power Mode)") }
        if Date() < vacationNoteUntil {
            let h = Int(vacationAway) / 3600, m = (Int(vacationAway) % 3600) / 60
            note("🌴 Vacation mode was on for \(h > 0 ? "\(h)h " : "")\(m)m — stats were paused")
        }
        for (label, v) in [("Fullness", s.belly), ("Hydration", s.hydration), ("Energy", s.energy), ("Happiness", s.happiness), ("Coat", s.coatCare)] {
            menu.addItem(statItem(label, v))
        }
        menu.addItem(.separator())
        menu.addItem(statItem("Food bowl", s.food))
        menu.addItem(statItem("Water bowl", s.water))
        menu.addItem(.separator())
        add(menu, "Hide Everything", #selector(toggleHidden)).keyEquivalent = "h"
        menu.addItem(.separator())
        add(menu, "Fill Food Bowl", #selector(fillFood))
        add(menu, "Fill Water Bowl", #selector(fillWater))
        menu.addItem(.separator())
        let left = s.treatsLeft
        add(menu, left > 0 ? "Give a Treat  (\(left) of \(s.treatsPerDay) left today)" : "No Treats Left Today",
            #selector(giveTreat)).isEnabled = treat == nil && left > 0
        add(menu, toy == nil ? "Toss a Yarn Ball" : "Put Yarn Away", #selector(toggleYarn))
        add(menu, "Release a Mouse", #selector(releaseMouse)).isEnabled = critter == nil
        add(menu, cat.isLongLoaf ? "Wake \(s.name) Up" : "Loaf for 30 Minutes", #selector(toggleLoaf))
        add(menu, cat.brushMode ? "Stop Brushing" : "Brush \(s.name)", #selector(toggleBrush))
        if hairball != nil { add(menu, "Clean Up Hairball", #selector(cleanHairball)) }
        add(menu, "Call \(s.name) Over", #selector(callCat))
        menu.addItem(.separator())
        let coatItem = NSMenuItem(title: "Coat", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, c) in coats.enumerated() {
            let it = NSMenuItem(title: c.name, action: #selector(pickCoat(_:)), keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == s.coat ? .on : .off
            sub.addItem(it)
        }
        coatItem.submenu = sub
        menu.addItem(coatItem)
        let persItem = NSMenuItem(title: "Mood", action: nil, keyEquivalent: "")
        let pm = NSMenu()
        for t in Personality.allCases {
            let it = NSMenuItem(title: t.name, action: #selector(pickPersonality(_:)), keyEquivalent: "")
            it.target = self; it.tag = t.rawValue; it.state = t == cat.trait ? .on : .off
            it.toolTip = t.blurb
            pm.addItem(it)
        }
        persItem.submenu = pm
        menu.addItem(persItem)
        let collarItem = NSMenuItem(title: "Collar", action: nil, keyEquivalent: "")
        let cm = NSMenu()
        let none = NSMenuItem(title: "No Collar", action: #selector(pickCollar(_:)), keyEquivalent: "")
        none.target = self; none.tag = -1; none.state = s.collarOn ? .off : .on
        cm.addItem(none)
        cm.addItem(.separator())
        for (name, hex) in AppDelegate.collarColors {
            let it = NSMenuItem(title: name, action: #selector(pickCollar(_:)), keyEquivalent: "")
            it.target = self; it.tag = hex
            it.state = s.collarOn && s.collarHex == hex ? .on : .off
            it.image = swatch(rgb(hex))
            cm.addItem(it)
        }
        cm.addItem(.separator())
        let custom = NSMenuItem(title: "Custom Color…", action: #selector(customCollar), keyEquivalent: "")
        custom.target = self
        if s.collarOn && !AppDelegate.collarColors.contains(where: { $0.1 == s.collarHex }) { custom.state = .on; custom.image = swatch(rgb(s.collarHex)) }
        cm.addItem(custom)
        collarItem.submenu = cm
        menu.addItem(collarItem)
        add(menu, "Rename…", #selector(rename))
        add(menu, "Settings…", #selector(openSettings)).keyEquivalent = ","
        add(menu, "Sounds", #selector(toggleSound)).state = s.sound ? .on : .off
        if #available(macOS 13.0, *) {
            add(menu, "Open at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(.separator())
        add(menu, "Quit Purrgram", #selector(quit))
    }

    @discardableResult
    func add(_ m: NSMenu, _ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self; m.addItem(it); return it
    }

    @objc func fillFood() { bowlView.fill(water: false) }
    @objc func fillWater() { bowlView.fill(water: true) }
    @objc func callCat() { cat.callOver() }

    func spawnProp(_ kind: ToyKind) -> (Toy, NSWindow, ToyView) {
        let v = world.vis
        let side: CGFloat = cat.x < v.midX ? 1 : -1
        let t = Toy(world: world, kind: kind, x: clampf(cat.x + side * rnd(140, 260), v.minX + 40, v.maxX - 40), y: min(cat.y + 280, v.maxY - 40))
        t.vx = -side * 40
        let w = makeWindow(NSRect(origin: P(t.x - ToyView.size.width / 2, t.y - PX), size: ToyView.size))
        let tv = ToyView(frame: NSRect(origin: .zero, size: ToyView.size))
        tv.toy = t; tv.cat = cat
        w.contentView = tv
        w.orderFrontRegardless(); restack()
        return (t, w, tv)
    }

    @objc func toggleYarn() {
        if toy != nil { removeYarn(); return }
        (toy, toyWin, toyView) = spawnProp(.yarn)
        cat.toy = toy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.cat.toyNoticed() }
    }

    func removeYarn() { toyWin?.orderOut(nil); toyWin = nil; toyView = nil; toy = nil; cat.toy = nil }

    @objc func giveTreat() {
        guard treat == nil, cat.s.treatsLeft > 0 else { return }
        cat.s.useTreat(); Store.save(cat.s)
        (treat, treatWin, treatView) = spawnProp(.treat)
        cat.treat = treat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.cat.treatNoticed() }
    }

    func removeTreat() { treatWin?.orderOut(nil); treatWin = nil; treatView = nil; treat = nil; cat.treat = nil }

    @objc func releaseMouse() {
        guard critter == nil else { return }
        let fromLeft = cat.x > world.vis.midX ? chance(0.75) : chance(0.25)   // usually from the far side
        let c = Critter(world: world, fromLeft: fromLeft)
        let w = makeWindow(NSRect(origin: P(c.x - CritterView.size.width / 2, c.y - PX), size: CritterView.size))
        let cv = CritterView(frame: NSRect(origin: .zero, size: CritterView.size))
        cv.critter = c
        w.contentView = cv
        w.orderFrontRegardless(); restack()
        critter = c; critterWin = w; critterView = cv; cat.critter = c
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.cat.critterNoticed() }
    }

    func dropHairball(at p: CGPoint, surface: Surface, rect: CGRect) {
        guard hairball == nil else { return }
        let t = Toy(world: world, kind: .hairball, x: p.x, y: p.y)
        t.surface = surface; t.surfRect = rect
        let w = makeWindow(NSRect(origin: P(t.x - ToyView.size.width / 2, t.y - PX), size: ToyView.size))
        let v = ToyView(frame: NSRect(origin: .zero, size: ToyView.size))
        v.toy = t; v.cat = cat
        w.contentView = v
        w.orderFrontRegardless(); restack()
        hairball = t; hairballWin = w; hairballView = v
    }

    func removeHairball() {
        hairballWin?.orderOut(nil); hairballWin = nil; hairballView = nil; hairball = nil; cat.hairballOut = false
    }

    @objc func cleanHairball() { removeHairball() }

    /// Tuck the cat, bowls and any toys away (and pause the cat), or bring them all back.
    @objc func toggleHidden() {
        allHidden.toggle()
        let wins = [bowlWin, toyWin, treatWin, critterWin, hairballWin, catWin].compactMap { $0 }
        if allHidden {
            wins.forEach { $0.orderOut(nil) }
            timer?.invalidate(); timer = nil   // nothing to draw: no wake-ups at all while tucked away
            Store.save(cat.s)
        } else {
            wins.forEach { $0.orderFrontRegardless() }
            restack()
            last = CACurrentMediaTime()
            nextMouseAt = last + rndD(8 * 60, 20 * 60)
            if !paused { setFPS(30) }
        }
    }

    @objc func toggleBrush() {
        cat.brushMode.toggle(); lastStroke = CACurrentMediaTime()
        if cat.brushMode { cat.callOver() }   // come here so you can brush
    }

    @objc func pickPersonality(_ sender: NSMenuItem) { cat.s.personality = sender.tag; Store.save(cat.s) }

    func removeMouse() { critterWin?.orderOut(nil); critterWin = nil; critterView = nil; critter = nil; cat.critter = nil }

    @objc func openSettings() {
        if settings == nil { settings = SettingsController(app: self) }
        settings?.show()
    }

    @objc func toggleLoaf() { if cat.isLongLoaf { cat.wakeUp() } else { cat.loafHere() } }

    // MARK: collar

    static let collarColors: [(String, Int)] = [("Red", 0xC8323C), ("Blue", 0x2F6FD6), ("Pink", 0xF06A9B), ("Green", 0x2E9E5B),
                                                ("Purple", 0x8A4FD0), ("Orange", 0xF08A24), ("Black", 0x2A2A2E)]

    func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
            NSColor.black.withAlphaComponent(0.3).setStroke(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).stroke()
            return true
        }
    }

    @objc func pickCollar(_ sender: NSMenuItem) {
        if sender.tag < 0 { cat.s.collarOn = false } else { cat.s.collarOn = true; cat.s.collarHex = sender.tag }
        Store.save(cat.s)
    }

    /// Opens the system color picker (wheel, sliders, swatches); the collar updates live as you drag.
    @objc func customCollar() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = rgb(cat.s.collarHex)
        panel.setTarget(self)
        panel.setAction(#selector(collarColorChanged(_:)))
        panel.isContinuous = true
        panel.title = "Collar Color"
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func collarColorChanged(_ sender: NSColorPanel) {
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8) | Int((c.blueComponent * 255).rounded())
        cat.s.collarOn = true; cat.s.collarHex = hex
        saveSoon()
    }
    @objc func pickCoat(_ sender: NSMenuItem) { cat.s.coat = sender.tag; Store.save(cat.s) }
    @objc func rename() { askName(first: false) }
    @objc func toggleSound() { cat.s.sound.toggle(); Store.save(cat.s) }
    @objc func quit() { Store.save(cat.s); NSApp.terminate(nil) }

    @objc func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Couldn't change the login setting"
            a.informativeText = "Move Purrgram into your Applications folder and try again.\n\n\(error.localizedDescription)"
            a.runModal()
        }
    }

    func askName(first: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = first ? "A cat has moved onto your desktop!" : "Rename your cat"
        a.informativeText = first
            ? "Keep the bowls in the bottom-right corner full by clicking them.\n\nClick the cat to pet. Double-click to shoo. Drag to pick up.\nThe 🐱 in the menu bar shows how they're doing.\n\nWhat's their name?"
            : "What should your cat be called?"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.stringValue = cat.s.name
        a.accessoryView = tf
        a.addButton(withTitle: "OK")
        if !first { a.addButton(withTitle: "Cancel") }
        a.window.initialFirstResponder = tf
        if a.runModal() == .alertFirstButtonReturn {
            let n = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { cat.s.name = String(n.prefix(24)) }
        }
        cat.s.named = true
        Store.save(cat.s)
        if first { cat.meow() }
    }
}
