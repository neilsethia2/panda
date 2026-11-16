import Combine
import Foundation
import UserNotifications

/// macOS notifications ("Not today! Get back to work.").
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    enum Permission: Equatable { case unknown, allowed, denied }

    @Published private(set) var permission: Permission = .unknown

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func start() {
        center.delegate = self
        refreshPermission()
    }

    func refreshPermission() {
        center.getNotificationSettings { [weak self] settings in
            let value: Permission
            switch settings.authorizationStatus {
            case .authorized, .provisional: value = .allowed
            case .denied: value = .denied
            default: value = .unknown
            }
            DispatchQueue.main.async { self?.permission = value }
        }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert]) { [weak self] _, _ in
            self?.refreshPermission()
        }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Reusing one identifier means repeated attempts replace each other instead of piling up.
        let request = UNNotificationRequest(identifier: "panda.block", content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

enum Lines {
    static let instagram = [
        "Not today! Get back to work.",
        "Panda caught you scrolling!",
        "Instagram can wait.",
        "Your future self says thank you.",
    ]

    static let shorts = [
        "That was a Short. Closed it.",
        "One Short is never just one.",
        "Shorts can wait. The real video can't.",
        "Nice try. Back to it.",
    ]

    static let youtube = [
        "YouTube is off limits right now.",
        "Later. Panda promises.",
    ]

    static func line(for kind: BlockKind) -> String {
        switch kind {
        case .instagram: return instagram.randomElement() ?? "Instagram can wait."
        case .shorts: return shorts.randomElement() ?? "That was a Short."
        case .youtube: return youtube.randomElement() ?? "Later."
        }
    }

    static func title(for kind: BlockKind) -> String {
        switch kind {
        case .instagram: return "Panda closed Instagram"
        case .shorts: return "Panda closed a YouTube Short"
        case .youtube: return "Panda closed YouTube"
        }
    }
}
