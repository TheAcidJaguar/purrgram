// DesktopCat — the Settings window.

import Cocoa
import ServiceManagement

// MARK: - Settings window

/// A small Preferences window for everything that doesn't need to live in the menu.
final class SettingsController: NSObject, NSWindowDelegate {
    weak var app: AppDelegate?
    var window: NSWindow!
    var nameField: NSTextField!, coatPop: NSPopUpButton!, moodPop: NSPopUpButton!
    var collarCheck: NSButton!, collarWell: NSColorWell!
    var sizeSlider: NSSlider!, sizeLabel: NSTextField!
    var treatStepper: NSStepper!, treatLabel: NSTextField!
    var soundCheck: NSButton!, litterCheck: NSButton!, hairballCheck: NSButton!, miceCheck: NSButton!, loginCheck: NSButton!
    var centered = false

    init(app: AppDelegate) {
        self.app = app
        super.init()
        build()
    }

    var cat: Cat { app!.cat }

    func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
    func row(_ views: NSView...) -> NSStackView {
        let st = NSStackView(views: views); st.orientation = .horizontal; st.spacing = 8; return st
    }

    func build() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Press Paws Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self

        nameField = NSTextField(string: ""); nameField.target = self; nameField.action = #selector(nameChanged)
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        coatPop = NSPopUpButton(); coatPop.addItems(withTitles: coats.map(\.name)); coatPop.target = self; coatPop.action = #selector(coatChanged)
        moodPop = NSPopUpButton(); moodPop.addItems(withTitles: Personality.allCases.map(\.name)); moodPop.target = self; moodPop.action = #selector(moodChanged)
        collarCheck = NSButton(checkboxWithTitle: "Wear a collar", target: self, action: #selector(collarChanged))
        collarWell = NSColorWell(); collarWell.target = self; collarWell.action = #selector(collarChanged)
        collarWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        collarWell.heightAnchor.constraint(equalToConstant: 22).isActive = true
        sizeSlider = NSSlider(value: 1, minValue: 0.7, maxValue: 1.4, target: self, action: #selector(sizeChanged))
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 170).isActive = true
        sizeLabel = label("100%")
        treatStepper = NSStepper(); treatStepper.minValue = 1; treatStepper.maxValue = 10; treatStepper.increment = 1
        treatStepper.target = self; treatStepper.action = #selector(treatsChanged)
        treatLabel = label("5")
        soundCheck = NSButton(checkboxWithTitle: "Sounds", target: self, action: #selector(togglesChanged))
        litterCheck = NSButton(checkboxWithTitle: "Litter box trips", target: self, action: #selector(togglesChanged))
        hairballCheck = NSButton(checkboxWithTitle: "Hairballs", target: self, action: #selector(togglesChanged))
        miceCheck = NSButton(checkboxWithTitle: "Mice wander in on their own", target: self, action: #selector(togglesChanged))
        loginCheck = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(loginChanged))

        let empty = NSGridCell.emptyContentView
        var rows: [[NSView]] = [
            [label("Name:"), nameField],
            [label("Coat:"), coatPop],
            [label("Mood:"), moodPop],
            [label("Collar:"), row(collarCheck, collarWell)],
            [label("Size:"), row(sizeSlider, sizeLabel)],
            [label("Treats per day:"), row(treatStepper, treatLabel)],
            [label("Behaviors:"), litterCheck], [empty, hairballCheck], [empty, miceCheck],
            [label("General:"), soundCheck],
        ]
        if #available(macOS 13.0, *) { rows.append([empty, loginCheck]) }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10; grid.columnSpacing = 12
        grid.row(at: 6).topPadding = 8; grid.row(at: 9).topPadding = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
        ])
        window.contentView = content
    }

    func load() {
        let s = cat.s
        if window.firstResponder !== nameField.currentEditor() { nameField.stringValue = s.name }   // don't clobber typing
        coatPop.selectItem(at: s.coat % coats.count)
        moodPop.selectItem(at: cat.trait.rawValue)
        collarCheck.state = s.collarOn ? .on : .off
        collarWell.color = rgb(s.collarHex)
        sizeSlider.doubleValue = s.sizeMul; sizeLabel.stringValue = "\(Int((s.sizeMul * 100).rounded()))%"
        treatStepper.integerValue = s.treatsPerDay; treatLabel.stringValue = "\(s.treatsPerDay)"
        soundCheck.state = s.sound ? .on : .off
        litterCheck.state = s.litterOn ? .on : .off
        hairballCheck.state = s.hairballsOn ? .on : .off
        miceCheck.state = s.miceOn ? .on : .off
        if #available(macOS 13.0, *) { loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off }
    }

    func show() {
        load()
        NSApp.activate(ignoringOtherApps: true)
        if !centered { window.center(); centered = true }
        window.makeKeyAndOrderFront(nil)
    }

    func save() { app?.saveSoon() }

    @objc func nameChanged() {
        let n = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { cat.s.name = String(n.prefix(24)); save() }
    }
    @objc func coatChanged() { cat.s.coat = coatPop.indexOfSelectedItem; save() }
    @objc func moodChanged() { cat.s.personality = moodPop.indexOfSelectedItem; save() }
    @objc func collarChanged() {
        cat.s.collarOn = collarCheck.state == .on
        if let c = collarWell.color.usingColorSpace(.sRGB) {
            cat.s.collarHex = (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8)
                | Int((c.blueComponent * 255).rounded())
        }
        save()
    }
    @objc func sizeChanged() {
        cat.s.sizeMul = (sizeSlider.doubleValue * 20).rounded() / 20
        sizeLabel.stringValue = "\(Int((cat.s.sizeMul * 100).rounded()))%"
        save()
    }
    @objc func treatsChanged() { cat.s.treatsPerDay = treatStepper.integerValue; treatLabel.stringValue = "\(cat.s.treatsPerDay)"; save() }
    @objc func togglesChanged() {
        cat.s.sound = soundCheck.state == .on
        cat.s.litterOn = litterCheck.state == .on
        cat.s.hairballsOn = hairballCheck.state == .on
        cat.s.miceOn = miceCheck.state == .on
        save()
    }
    @objc func loginChanged() {
        guard #available(macOS 13.0, *) else { return }
        let want = loginCheck.state == .on
        if want != (SMAppService.mainApp.status == .enabled) { app?.toggleLogin() }
        load()
    }
}
