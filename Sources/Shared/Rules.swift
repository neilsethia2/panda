import Foundation

// Code shared by the Panda app and the tiny native-messaging host that Chrome talks to.
// Nothing in here touches the network. Everything is local files and string checks.

enum BlockKind: String, Codable {
    case instagram
    case shorts
    case youtube

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .shorts: return "a YouTube Short"
        case .youtube: return "YouTube"
        }
    }
}

/// The handful of settings the blocking decision depends on. The app writes this to disk
/// every time a toggle changes, and the native host reads it when Chrome asks for a verdict.
struct SharedSettings: Codable, Equatable {
    var master: Bool = true
    var instagram: Bool = true
    var youtube: Bool = true
    var shorts: Bool = true
    var allowNormalVideos: Bool = true
    /// How long the browser waits before closing the tab, so Panda has time to run over to it.
    var closeDelayMs: Int = 0

    init() {}

    enum CodingKeys: String, CodingKey {
        case master, instagram, youtube, shorts, allowNormalVideos, closeDelayMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        master = try c.decodeIfPresent(Bool.self, forKey: .master) ?? true
        instagram = try c.decodeIfPresent(Bool.self, forKey: .instagram) ?? true
        youtube = try c.decodeIfPresent(Bool.self, forKey: .youtube) ?? true
        shorts = try c.decodeIfPresent(Bool.self, forKey: .shorts) ?? true
        allowNormalVideos = try c.decodeIfPresent(Bool.self, forKey: .allowNormalVideos) ?? true
        closeDelayMs = try c.decodeIfPresent(Int.self, forKey: .closeDelayMs) ?? 0
    }

    static func load() -> SharedSettings {
        guard let data = try? Data(contentsOf: PandaPaths.settingsFile),
              let decoded = try? JSONDecoder().decode(SharedSettings.self, from: data) else {
            return SharedSettings()
        }
        return decoded
    }

    func save() {
        PandaPaths.ensureSupportDir()
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: PandaPaths.settingsFile, options: .atomic)
        }
    }
}

enum PandaPaths {
    static let bundleID = "com.neilsethia.Panda"
    static let hostName = "com.neilsethia.panda"
    static let extensionID = "nmccijffhnjhgjkpaldfpignpemkfbkm"
    static let eventNotification = "com.neilsethia.panda.event"

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Panda", isDirectory: true)
    }

    static var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    static var statsFile: URL { supportDir.appendingPathComponent("stats.json") }
    static var presenceDir: URL { supportDir.appendingPathComponent("hosts", isDirectory: true) }
    static var extensionDir: URL { supportDir.appendingPathComponent("ChromeExtension", isDirectory: true) }

    static func ensureSupportDir() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
    }
}

enum Rules {
    /// What a URL is, regardless of settings. Returns nil for anything Panda does not care about.
    static func classify(_ urlString: String) -> BlockKind? {
        guard let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = components.host?.lowercased() else {
            return nil
        }
        if host.hasSuffix(".") { host.removeLast() }

        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return .instagram
        }

        let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        guard isYouTube else { return nil }

        let path = components.path.lowercased()
        if path == "/shorts" || path.hasPrefix("/shorts/") {
            return .shorts
        }
        return .youtube
    }

    /// Whether this URL should be closed right now, given the current settings.
    static func verdict(for urlString: String, settings: SharedSettings) -> BlockKind? {
        guard settings.master, let kind = classify(urlString) else { return nil }
        switch kind {
        case .instagram:
            return settings.instagram ? .instagram : nil
        case .shorts:
            guard settings.youtube else { return nil }
            if settings.shorts { return .shorts }
            return settings.allowNormalVideos ? nil : .youtube
        case .youtube:
            guard settings.youtube else { return nil }
            return settings.allowNormalVideos ? nil : .youtube
        }
    }
}
