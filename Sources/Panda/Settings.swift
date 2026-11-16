import Combine
import Foundation

enum CompanionMode: String, CaseIterable, Identifiable {
    case always
    case onCatch
    case menuBarOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: return "Always on screen"
        case .onCatch: return "Only when he catches you"
        case .menuBarOnly: return "Menu bar only"
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

    @Published var master: Bool { didSet { changed() } }
    @Published var instagram: Bool { didSet { changed() } }
    @Published var youtube: Bool { didSet { changed() } }
    @Published var shorts: Bool { didSet { changed() } }
    @Published var allowNormalVideos: Bool { didSet { changed() } }

    @Published var companionMode: CompanionMode { didSet { changed() } }
    @Published var walkToTab: Bool { didSet { changed() } }
    @Published var notifications: Bool { didSet { changed() } }
    @Published var automationFallback: Bool { didSet { changed() } }
    @Published var hasOnboarded: Bool { didSet { changed() } }

    /// How long Panda takes to run to the tab. The tab is closed the moment he arrives.
    static let walkDuration: TimeInterval = 0.55

    private init() {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
        }
        master = bool("master", true)
        instagram = bool("instagram", true)
        youtube = bool("youtube", true)
        shorts = bool("shorts", true)
        allowNormalVideos = bool("allowNormalVideos", true)
        companionMode = CompanionMode(rawValue: UserDefaults.standard.string(forKey: "companionMode") ?? "") ?? .always
        walkToTab = bool("walkToTab", true)
        notifications = bool("notifications", true)
        automationFallback = bool("automationFallback", true)
        hasOnboarded = bool("hasOnboarded", false)
        loading = false
        writeShared()
    }

    /// Master switch plus at least one thing to block.
    var protectionActive: Bool { master }

    /// True when a Shorts tab would be closed right now.
    var shortsBlocked: Bool { master && youtube && shorts }

    /// True when an Instagram tab would be closed right now.
    var instagramBlocked: Bool { master && instagram }

    var anythingBlocked: Bool {
        master && (instagram || (youtube && (shorts || !allowNormalVideos)))
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
        return s
    }

    private func changed() {
        guard !loading else { return }
        defaults.set(master, forKey: "master")
        defaults.set(instagram, forKey: "instagram")
        defaults.set(youtube, forKey: "youtube")
        defaults.set(shorts, forKey: "shorts")
        defaults.set(allowNormalVideos, forKey: "allowNormalVideos")
        defaults.set(companionMode.rawValue, forKey: "companionMode")
        defaults.set(walkToTab, forKey: "walkToTab")
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
