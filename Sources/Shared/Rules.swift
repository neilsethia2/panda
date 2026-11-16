import Foundation

// Code shared by the Panda app and the tiny native-messaging host that Chrome talks to.
// Nothing in here touches the network. Everything is local files and string checks.

enum BlockKind: String, Codable {
    case instagram
    case shorts
    case youtube
    case custom   // a site from the user's own blocklist

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .shorts: return "a YouTube Short"
        case .youtube: return "YouTube"
        case .custom: return "a site on your blocklist"
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
    /// The user's own blocklist. Each entry is "host" (whole site) or "host/path" (one page or section).
    var customOn: Bool = true
    var custom: [String] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case master, instagram, youtube, shorts, allowNormalVideos, closeDelayMs, customOn, custom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        master = try c.decodeIfPresent(Bool.self, forKey: .master) ?? true
        instagram = try c.decodeIfPresent(Bool.self, forKey: .instagram) ?? true
        youtube = try c.decodeIfPresent(Bool.self, forKey: .youtube) ?? true
        shorts = try c.decodeIfPresent(Bool.self, forKey: .shorts) ?? true
        allowNormalVideos = try c.decodeIfPresent(Bool.self, forKey: .allowNormalVideos) ?? true
        closeDelayMs = try c.decodeIfPresent(Int.self, forKey: .closeDelayMs) ?? 0
        customOn = try c.decodeIfPresent(Bool.self, forKey: .customOn) ?? true
        custom = try c.decodeIfPresent([String].self, forKey: .custom) ?? []
    }

    /// Just the host names on the blocklist, for the browser extension's quick first check.
    var customHosts: [String] {
        guard master, customOn else { return [] }
        var seen = Set<String>()
        return custom.compactMap { entry -> String? in
            let host = String(entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            return host.isEmpty || !seen.insert(host).inserted ? nil : host
        }
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
        guard settings.master else { return nil }
        if let builtIn = builtInVerdict(for: urlString, settings: settings) { return builtIn }
        if settings.customOn, matchesCustom(urlString, entries: settings.custom) { return .custom }
        return nil
    }

    private static func builtInVerdict(for urlString: String, settings: SharedSettings) -> BlockKind? {
        guard let kind = classify(urlString) else { return nil }
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
        case .custom:
            return nil
        }
    }

    // MARK: The user's own blocklist

    /// Turns whatever the user pasted into a blocklist entry.
    /// "https://www.Reddit.com/r/all/?x=1" becomes "reddit.com" (whole site) or
    /// "reddit.com/r/all" (only that page and anything under it).
    static func normalizeEntry(_ raw: String, wholeSite: Bool) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        if wholeSite { return host }

        var path = components.path.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        var entry = host + path
        // Keep the video id for links like youtube.com/watch?v=..., where the path alone means nothing.
        if let query = components.percentEncodedQuery, !query.isEmpty, path == "/watch" || path.isEmpty {
            entry += "?" + query
        }
        return entry
    }

    static func matchesCustom(_ urlString: String, entries: [String]) -> Bool {
        guard !entries.isEmpty,
              let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = components.host?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        var path = components.path.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        let queryItems = Set((components.percentEncodedQuery ?? "").split(separator: "&").map(String.init))

        for entry in entries {
            var rest = Substring(entry)
            var entryQuery: Substring = ""
            if let mark = rest.firstIndex(of: "?") {
                entryQuery = rest[rest.index(after: mark)...]
                rest = rest[..<mark]
            }
            let entryHost: Substring
            var entryPath: Substring = ""
            if let slash = rest.firstIndex(of: "/") {
                entryHost = rest[..<slash]
                entryPath = rest[slash...]
            } else {
                entryHost = rest
            }
            guard !entryHost.isEmpty else { continue }
            guard host == entryHost || host.hasSuffix("." + entryHost) else { continue }

            if !entryPath.isEmpty {
                guard path.hasPrefix(entryPath) else { continue }
                // "/r/all" must not match "/r/allthethings"
                let after = path.dropFirst(entryPath.count)
                guard after.isEmpty || after.hasPrefix("/") else { continue }
            }
            if !entryQuery.isEmpty {
                let wanted = Set(entryQuery.split(separator: "&").map(String.init))
                guard wanted.isSubset(of: queryItems) else { continue }
            }
            return true
        }
        return false
    }
}

/// Off unless the app is started with --verbose (or the host with PANDA_VERBOSE=1).
/// Writes plain lines to debug.log next to the statistics file. Never records addresses.
enum DebugLog {
    static let enabled: Bool = CommandLine.arguments.contains("--verbose")
        || ProcessInfo.processInfo.environment["PANDA_VERBOSE"] == "1"

    static func write(_ text: String) {
        guard enabled else { return }
        PandaPaths.ensureSupportDir()
        let line = "\(Date()) [\(ProcessInfo.processInfo.processName)] \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = PandaPaths.supportDir.appendingPathComponent("debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
