import AppKit
import Foundation

/// Everything to do with the browser extension: putting a copy of it somewhere stable,
/// registering the native-messaging host with each Chromium browser, and knowing which
/// browsers currently have a live extension.
enum ExtensionBridge {
    struct ChromiumBrowser {
        let name: String
        let bundleID: String
        /// Path under ~/Library/Application Support
        let supportPath: String
    }

    static let chromiumBrowsers: [ChromiumBrowser] = [
        ChromiumBrowser(name: "Google Chrome", bundleID: "com.google.Chrome", supportPath: "Google/Chrome"),
        ChromiumBrowser(name: "Chrome Beta", bundleID: "com.google.Chrome.beta", supportPath: "Google/Chrome Beta"),
        ChromiumBrowser(name: "Chrome Canary", bundleID: "com.google.Chrome.canary", supportPath: "Google/Chrome Canary"),
        ChromiumBrowser(name: "Arc", bundleID: "company.thebrowser.Browser", supportPath: "Arc/User Data"),
        ChromiumBrowser(name: "Brave", bundleID: "com.brave.Browser", supportPath: "BraveSoftware/Brave-Browser"),
        ChromiumBrowser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", supportPath: "Microsoft Edge"),
        ChromiumBrowser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", supportPath: "Vivaldi"),
        ChromiumBrowser(name: "Chromium", bundleID: "org.chromium.Chromium", supportPath: "Chromium"),
    ]

    /// macOS runs freshly downloaded apps from a hidden read-only copy until they are moved.
    /// Registering that temporary path with Chrome would break as soon as the app quits.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static var isRunningFromDiskImage: Bool {
        Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }

    static var hostExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/panda-host")
    }

    static var bundledExtension: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension", isDirectory: true)
    }

    /// The folder the user points Chrome at ("Load unpacked").
    static var extensionFolder: URL { PandaPaths.extensionDir }

    /// Browsers that are actually installed on this Mac (their profile folder exists).
    static var installedChromiumBrowsers: [ChromiumBrowser] {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return chromiumBrowsers.filter { browser in
            guard let base = base else { return false }
            return fm.fileExists(atPath: base.appendingPathComponent(browser.supportPath).path)
        }
    }

    /// Run at every launch. Idempotent and quick.
    static func install() {
        PandaPaths.ensureSupportDir()
        copyExtensionIfNeeded()
        guard !isTranslocated, !isRunningFromDiskImage else { return }
        writeHostManifests()
    }

    private static func copyExtensionIfNeeded() {
        let fm = FileManager.default
        guard let source = bundledExtension, fm.fileExists(atPath: source.path) else { return }
        let destination = extensionFolder

        // Only rewrite when the bundled copy differs, so a loaded extension is not disturbed.
        let bundledManifest = try? Data(contentsOf: source.appendingPathComponent("manifest.json"))
        let installedManifest = try? Data(contentsOf: destination.appendingPathComponent("manifest.json"))
        let bundledWorker = try? Data(contentsOf: source.appendingPathComponent("background.js"))
        let installedWorker = try? Data(contentsOf: destination.appendingPathComponent("background.js"))
        if bundledManifest != nil, bundledManifest == installedManifest, bundledWorker == installedWorker {
            return
        }

        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        copyContents(of: source, to: destination)
    }

    private static func copyContents(of source: URL, to destination: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                copyContents(of: item, to: target)
            } else if let data = try? Data(contentsOf: item) {
                try? data.write(to: target, options: .atomic)
            }
        }
    }

    private static func writeHostManifests() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let manifest: [String: Any] = [
            "name": PandaPaths.hostName,
            "description": "Panda anti-doomscrolling companion",
            "path": hostExecutable.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(PandaPaths.extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return }

        for browser in chromiumBrowsers {
            let root = base.appendingPathComponent(browser.supportPath)
            guard fm.fileExists(atPath: root.path) else { continue }
            let folder = root.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(PandaPaths.hostName).json")
            if let existing = try? Data(contentsOf: file), existing == data { continue }
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Which browsers have a live extension

    struct Connection: Equatable {
        let pid: Int32
        let bundleID: String
        let name: String
    }

    /// Reads the tiny presence files the host leaves while a browser has the extension running.
    static func connections() -> [Connection] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: PandaPaths.presenceDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var live: [Connection] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pidValue = object["pid"] as? Int else {
                try? fm.removeItem(at: file)
                continue
            }
            let pid = Int32(pidValue)
            // Signal 0 checks that the process still exists without touching it.
            if pid > 0, kill(pid, 0) == 0 {
                live.append(Connection(
                    pid: pid,
                    bundleID: object["bundle"] as? String ?? "",
                    name: object["name"] as? String ?? "Browser"
                ))
            } else {
                try? fm.removeItem(at: file)
            }
        }
        return live
    }

    static func isExtensionConnected(bundleID: String) -> Bool {
        connections().contains { $0.bundleID == bundleID }
    }

    static var connectedBrowserNames: [String] {
        var seen = Set<String>()
        return connections().map { $0.name }.filter { seen.insert($0).inserted }.sorted()
    }

    // MARK: Helping the user install it

    static func revealExtensionFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([extensionFolder])
    }

    static func copyExtensionPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(extensionFolder.path, forType: .string)
    }

    /// Opens the extensions page in the given browser. Browsers refuse chrome:// links from
    /// other apps in some versions, so the setup screen also tells the user what to type.
    static func openExtensionsPage(in browser: ChromiumBrowser) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID),
              let page = URL(string: "chrome://extensions") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([page], withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }
}
