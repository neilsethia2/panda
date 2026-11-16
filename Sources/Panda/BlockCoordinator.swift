import AppKit
import Combine
import Foundation

/// The middle of the app. Hears about blocked tabs (from the browser extension through the
/// native host, or from the Automation watcher), then updates statistics, the panda, the
/// menu bar and notifications. Also owns the "time protected" clock and the focus streak.
final class BlockCoordinator: NSObject, ObservableObject {
    let settings: AppSettings
    let stats: StatsStore
    let watcher: BrowserWatcher
    let companion: CompanionController

    /// Something visible should refresh (menu bar icon, setup screen).
    var onStateChanged: (() -> Void)?

    /// Bumped whenever browser access or extension connections may have changed.
    @Published var refreshToken = 0

    private var streakTimer: Timer?
    private var asleep = false

    /// Minutes of uninterrupted focus before the panda celebrates.
    static let streakMinutes = 25

    init(settings: AppSettings, stats: StatsStore, companion: CompanionController) {
        self.settings = settings
        self.stats = stats
        self.companion = companion
        self.watcher = BrowserWatcher(settings: settings)
        super.init()

        watcher.onCaught = { [weak self] kind, _, anchor, delay in
            self?.caught(kind: kind, anchor: anchor, delay: delay)
        }
        watcher.onClosed = { [weak self] kind, browser in
            self?.closed(kind: kind, browser: browser)
        }
        watcher.onAccessChanged = { [weak self] in
            self?.refreshToken += 1
            self?.onStateChanged?()
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(hostEvent(_:)),
            name: Notification.Name(PandaPaths.eventNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        companion.onPoke = { [weak self] in self?.poked() }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Apply the current settings everywhere. Called at launch and after every toggle.
    func settingsChanged() {
        stats.setProtectionActive(settings.protectionActive && !asleep)
        watcher.reevaluate()
        companion.refresh()
        scheduleStreak()
        onStateChanged?()
    }

    // MARK: Events from the browser extension

    @objc private func hostEvent(_ note: Notification) {
        guard let json = note.object as? String,
              let data = json.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = payload["event"] as? String,
              let kind = BlockKind(rawValue: payload["kind"] as? String ?? "") else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch event {
            case "caught":
                var anchor: NSPoint?
                if let left = payload["left"] as? Double,
                   let top = payload["top"] as? Double,
                   let width = payload["width"] as? Double,
                   let index = payload["index"] as? Double,
                   let count = payload["count"] as? Double {
                    anchor = TabGeometry.anchor(
                        family: .chromium, left: left, top: top, width: width,
                        index: Int(index), count: Int(count), pinned: Int(payload["pinned"] as? Double ?? 0)
                    )
                }
                let delay = (payload["delayMs"] as? Double ?? 0) / 1000
                self.caught(kind: kind, anchor: anchor, delay: delay)
            case "closed":
                self.closed(kind: kind, browser: payload["browser"] as? String ?? "your browser")
            default:
                break
            }
            self.refreshToken += 1
        }
    }

    // MARK: What happens when something is blocked

    private func caught(kind: BlockKind, anchor: NSPoint?, delay: TimeInterval) {
        companion.pounce(to: anchor, travel: delay, kind: kind)
    }

    private func closed(kind: BlockKind, browser: String) {
        stats.record(kind)
        let line = Lines.line(for: kind)
        companion.confirmCatch(message: line)
        if settings.notifications {
            Notifier.shared.post(title: Lines.title(for: kind), body: line)
        }
        scheduleStreak()
        onStateChanged?()
    }

    private func poked() {
        let today = stats.today.total
        if !settings.protectionActive {
            companion.chat("Zzz… flip the switch in the menu bar to wake me.")
        } else if today == 0 {
            companion.chat("Nothing blocked today. Look at you go.")
        } else if today == 1 {
            companion.chat("1 distraction blocked today.")
        } else {
            companion.chat("\(today) distractions blocked today.")
        }
    }

    // MARK: Focus streak

    /// One-shot timer: if nothing gets blocked for a while, the panda celebrates.
    private func scheduleStreak() {
        streakTimer?.invalidate()
        streakTimer = nil
        guard settings.anythingBlocked, !asleep else { return }
        let timer = Timer(timeInterval: TimeInterval(BlockCoordinator.streakMinutes * 60), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.companion.celebrate(message: "\(BlockCoordinator.streakMinutes) minutes without a single scroll!")
            self.scheduleStreak()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        streakTimer = timer
    }

    // MARK: Sleep and wake

    @objc private func willSleep() {
        asleep = true
        stats.setProtectionActive(false)
        watcher.stop()
        streakTimer?.invalidate()
        streakTimer = nil
    }

    @objc private func didWake() {
        asleep = false
        settingsChanged()
    }

    func shutdown() {
        stats.flush()
    }
}
