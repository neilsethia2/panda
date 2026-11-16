import Combine
import Foundation

enum CompanionMode: String, CaseIterable, Identifiable {
    case onCatch
    case always
    case menuBarOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onCatch: return "Only when he closes something"
        case .always: return "Always on screen"
        case .menuBarOnly: return "Never"
        }
    }
}

/// Where the character comes from when he runs to a tab.
enum EntrySide: String, CaseIterable, Identifiable {
    case left
    case right
    case nearest
    case top
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left side"
        case .right: return "Right side"
        case .nearest: return "Nearest side"
        case .top: return "Top"
        case .home: return "His resting spot"
        }
    }
}

enum CompanionSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var points: Double {
        switch self {
        case .small: return 52
        case .medium: return 72
        case .large: return 100
        }
    }
}

enum CharacterStyle: String, CaseIterable, Identifiable {
    case panda
    case custom

    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match the Mac"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Every preference Panda has. Stored in UserDefaults, so it survives restarts.
/// The blocking-related part is mirrored to a small JSON file that the browser bridge reads.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private var loading = true

    /// Called after any change, once the new values are saved.
    var onChange: (() -> Void)?

    // What gets blocked
    @Published var master: Bool { didSet { changed() } }
    @Published var instagram: Bool { didSet { changed() } }
    @Published var youtube: Bool { didSet { changed() } }
    @Published var shorts: Bool { didSet { changed() } }
    @Published var allowNormalVideos: Bool { didSet { changed() } }
    @Published var customOn: Bool { didSet { changed() } }
    /// Entries like "reddit.com" or "youtube.com/@somechannel".
    @Published var customSites: [String] { didSet { changed() } }

    // The character
    @Published var companionMode: CompanionMode { didSet { changed() } }
    @Published var entrySide: EntrySide { didSet { changed() } }
    @Published var companionSize: CompanionSize { didSet { changed() } }
    @Published var walkToTab: Bool { didSet { changed() } }
    @Published var showBubble: Bool { didSet { changed() } }
    @Published var characterStyle: CharacterStyle { didSet { changed() } }
    @Published var removeImageBackground: Bool { didSet { changed() } }
    @Published var flipWhenWalkingLeft: Bool { didSet { changed() } }

    // General
    @Published var appearance: AppearanceMode { didSet { changed() } }
    @Published var notifications: Bool { didSet { changed() } }
    @Published var automationFallback: Bool { didSet { changed() } }
    @Published var hasOnboarded: Bool { didSet { changed() } }

    /// Bumped when the light/dark theme flips, so every screen redraws. Not saved.
    @Published var themeToken = 0

    /// How long the character takes to run to the tab. The tab is closed the moment he arrives.
    static let walkDuration: TimeInterval = 0.55

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        master = bool("master", true)
        instagram = bool("instagram", true)
        youtube = bool("youtube", true)
        shorts = bool("shorts", true)
        allowNormalVideos = bool("allowNormalVideos", true)
        customOn = bool("customOn", true)
        customSites = d.stringArray(forKey: "customSites") ?? []

        companionMode = CompanionMode(rawValue: d.string(forKey: "companionMode") ?? "") ?? .onCatch
        entrySide = EntrySide(rawValue: d.string(forKey: "entrySide") ?? "") ?? .left
        companionSize = CompanionSize(rawValue: d.string(forKey: "companionSize") ?? "") ?? .medium
        walkToTab = bool("walkToTab", true)
        showBubble = bool("showBubble", true)
        characterStyle = CharacterStyle(rawValue: d.string(forKey: "characterStyle") ?? "") ?? .panda
        removeImageBackground = bool("removeImageBackground", true)
        flipWhenWalkingLeft = bool("flipWhenWalkingLeft", true)

        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        notifications = bool("notifications", true)
        automationFallback = bool("automationFallback", true)
        hasOnboarded = bool("hasOnboarded", false)
        loading = false
        writeShared()
    }

    var protectionActive: Bool { master }

    var customBlocked: Bool { master && customOn && !customSites.isEmpty }

    var anythingBlocked: Bool {
        master && (instagram || (youtube && (shorts || !allowNormalVideos)) || (customOn && !customSites.isEmpty))
    }

    var closeDelay: TimeInterval {
        (companionMode != .menuBarOnly && walkToTab) ? AppSettings.walkDuration : 0
    }

    var shared: SharedSettings {
        var s = SharedSettings()
        s.master = master
        s.instagram = instagram
        s.youtube = youtube
        s.shorts = shorts
        s.allowNormalVideos = allowNormalVideos
        s.closeDelayMs = Int(closeDelay * 1000)
        s.customOn = customOn
        s.custom = customSites
        return s
    }

    // MARK: Blocklist

    enum AddResult: Equatable {
        case added(String)
        case duplicate(String)
        case invalid
    }

    /// Add whatever the user pasted. `wholeSite` blocks the entire site; otherwise only
    /// that page and anything underneath it.
    @discardableResult
    func addCustomSite(_ raw: String, wholeSite: Bool) -> AddResult {
        guard let entry = Rules.normalizeEntry(raw, wholeSite: wholeSite) else { return .invalid }
        if customSites.contains(entry) { return .duplicate(entry) }
        customSites.append(entry)
        if !customOn { customOn = true }
        return .added(entry)
    }

    func removeCustomSite(_ entry: String) {
        customSites.removeAll { $0 == entry }
    }

    // MARK: Saving

    private func changed() {
        guard !loading else { return }
        defaults.set(master, forKey: "master")
        defaults.set(instagram, forKey: "instagram")
        defaults.set(youtube, forKey: "youtube")
        defaults.set(shorts, forKey: "shorts")
        defaults.set(allowNormalVideos, forKey: "allowNormalVideos")
        defaults.set(customOn, forKey: "customOn")
        defaults.set(customSites, forKey: "customSites")
        defaults.set(companionMode.rawValue, forKey: "companionMode")
        defaults.set(entrySide.rawValue, forKey: "entrySide")
        defaults.set(companionSize.rawValue, forKey: "companionSize")
        defaults.set(walkToTab, forKey: "walkToTab")
        defaults.set(showBubble, forKey: "showBubble")
        defaults.set(characterStyle.rawValue, forKey: "characterStyle")
        defaults.set(removeImageBackground, forKey: "removeImageBackground")
        defaults.set(flipWhenWalkingLeft, forKey: "flipWhenWalkingLeft")
        defaults.set(appearance.rawValue, forKey: "appearance")
        defaults.set(notifications, forKey: "notifications")
        defaults.set(automationFallback, forKey: "automationFallback")
        defaults.set(hasOnboarded, forKey: "hasOnboarded")
        writeShared()
        onChange?()
    }

    private func writeShared() {
        shared.save()
    }
}
