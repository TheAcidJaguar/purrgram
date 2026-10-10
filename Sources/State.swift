// DesktopCat — saved state (stats, settings) and crash-safe storage.

import Cocoa

// MARK: - Save state

struct SaveState: Codable {
    var name = "Mochi"
    var coat = 0
    var belly = 0.8, hydration = 0.8, energy = 0.9, happiness = 0.8
    var food = 0.6, water = 0.6
    var sound = true
    var named = false
    var saved = Date()

    /// Treats left today (the count resets at midnight).
    var treatsLeft: Int {
        let today = SaveState.dayStamp()
        return treatDay == today ? max(0, treatsPerDay - treatsUsed) : treatsPerDay
    }
    mutating func useTreat() {
        let today = SaveState.dayStamp()
        if treatDay != today { treatDay = today; treatsUsed = 0 }
        treatsUsed += 1
    }
    static func dayStamp() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    var collarOn = true
    var collarHex = 0xC8323C
    var coatCare = 0.8          // brushed and glossy (1) … matted (0)
    var personality = -1        // Personality raw value; picked at random on first launch
    // settings
    var sizeMul = 1.0           // on-screen size
    var litterOn = true, hairballsOn = true, miceOn = true
    var treatsPerDay = 5
    var treatDay = "", treatsUsed = 0

    init() {}

    /// Decode field by field so older save files (missing newer fields) still load.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? def }
        name = v(.name, name); coat = v(.coat, coat)
        belly = v(.belly, belly); hydration = v(.hydration, hydration); energy = v(.energy, energy); happiness = v(.happiness, happiness)
        food = v(.food, food); water = v(.water, water)
        sound = v(.sound, sound); named = v(.named, named); saved = v(.saved, saved)
        collarOn = v(.collarOn, collarOn); collarHex = v(.collarHex, collarHex)
        coatCare = v(.coatCare, coatCare); personality = v(.personality, personality)
        sizeMul = v(.sizeMul, sizeMul); litterOn = v(.litterOn, litterOn); hairballsOn = v(.hairballsOn, hairballsOn)
        miceOn = v(.miceOn, miceOn); treatsPerDay = v(.treatsPerDay, treatsPerDay)
        treatDay = v(.treatDay, treatDay); treatsUsed = v(.treatsUsed, treatsUsed)
    }
}

enum Store {
    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopCat", isDirectory: true)   // kept from the old name so existing cats carry over
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var url: URL { dir.appendingPathComponent("state.json") }
    static var backupURL: URL { dir.appendingPathComponent("state.backup.json") }

    /// The cat's needs only change while your Mac is awake and the app is running, so loading is just a read.
    /// If the main save is unreadable (e.g. a crash mid-write), fall back to the backup copy.
    static func load() -> SaveState {
        for u in [url, backupURL] {
            if let data = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(SaveState.self, from: data) { return s }
        }
        return SaveState()
    }

    /// Writes atomically, and keeps the previous good save as a backup.
    static func save(_ s: SaveState) {
        var s = s; s.saved = Date()
        guard let d = try? JSONEncoder().encode(s) else { return }
        if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(SaveState.self, from: old)) != nil {
            try? old.write(to: backupURL, options: .atomic)
        }
        try? d.write(to: url, options: .atomic)
    }
}
