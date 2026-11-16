import Foundation
import ServiceManagement

/// "Start Panda when I log in."
/// Uses the modern login-item API first. If macOS refuses (it can for apps that are not
/// signed with a paid developer certificate), falls back to a plain LaunchAgent that simply
/// opens the app at login.
enum LoginItem {
    private static let agentLabel = "com.neilsethia.panda.launcher"

    private static var agentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                removeAgent()
                return true
            } catch {
                return writeAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
            return true
        }
    }

    private static func writeAgent() -> Bool {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        do {
            let folder = agentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}
