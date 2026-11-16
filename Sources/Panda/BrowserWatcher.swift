import AppKit
import Foundation

/// Rough on-screen position of a tab, worked out from the window's position and the tab's
/// index. It only has to be close enough for the panda to land on the right tab, and it
/// means Panda never needs the Accessibility permission.
enum TabGeometry {
    enum Family { case chromium, safari }

    /// `left`, `top` and `width` use the browser's coordinate space: points from the top-left
    /// corner of the main display. Returns a point in AppKit screen coordinates (origin bottom-left).
    static func anchor(family: Family, left: Double, top: Double, width: Double,
                       index: Int, count: Int, pinned: Int) -> NSPoint? {
        guard width > 100, count > 0, let primary = NSScreen.screens.first else { return nil }
        let x: Double
        let yFromTop: Double

        switch family {
        case .chromium:
            let leftInset = 112.0   // traffic lights and the tab-search button
            let rightInset = 56.0   // new-tab button
            let pinnedWidth = 42.0
            let pinnedCount = max(0, min(pinned, count))
            let normalCount = max(1, count - pinnedCount)
            let available = max(60, width - leftInset - rightInset - Double(pinnedCount) * pinnedWidth)
            let tabWidth = min(232.0, available / Double(normalCount))
            if index < pinnedCount {
                x = left + leftInset + (Double(index) + 0.5) * pinnedWidth
            } else {
                let position = Double(index - pinnedCount)
                x = left + leftInset + Double(pinnedCount) * pinnedWidth + position * tabWidth + tabWidth - 18
            }
            yFromTop = top + 22
        case .safari:
            if count <= 1 {
                x = left + width / 2
                yFromTop = top + 28
            } else {
                let tabWidth = width / Double(count)
                x = left + (Double(index) + 0.5) * tabWidth
                yFromTop = top + 66
            }
        }

        return NSPoint(x: x, y: Double(primary.frame.maxY) - yFromTop)
    }
}

/// Watches browsers that do not have the Panda extension, using macOS Automation
/// (the same mechanism AppleScript uses). Safari always goes through here.
///
/// Battery: the check only runs while one of those browsers is the frontmost app and
/// protection is on. It is one lightweight question per second ("what is the address of
/// the tab in front?"), and it stops the moment you switch to another app.
final class BrowserWatcher: NSObject {
    struct Browser {
        let bundleID: String
        let name: String
        let family: TabGeometry.Family
    }

    enum Access: Equatable { case unknown, allowed, denied }

    static let browsers: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari", family: .safari),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview", family: .safari),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome", family: .chromium),
        Browser(bundleID: "com.google.Chrome.beta", name: "Chrome Beta", family: .chromium),
        Browser(bundleID: "com.google.Chrome.canary", name: "Chrome Canary", family: .chromium),
        Browser(bundleID: "com.brave.Browser", name: "Brave", family: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", family: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", family: .chromium),
        Browser(bundleID: "org.chromium.Chromium", name: "Chromium", family: .chromium),
    ]

    /// (kind, browser name, where the tab is, seconds until it closes)
    var onCaught: ((BlockKind, String, NSPoint?, TimeInterval) -> Void)?
    /// (kind, browser name)
    var onClosed: ((BlockKind, String) -> Void)?
    var onAccessChanged: (() -> Void)?

    private let settings: AppSettings
    private let queue = DispatchQueue(label: "com.neilsethia.panda.browserwatcher", qos: .utility)
    private var timer: Timer?
    private var current: Browser?
    private var scripts: [String: NSAppleScript] = [:]   // touched only on `queue`
    private var checking = false                          // touched only on main
    private var closing = Set<String>()                   // touched only on main
    private(set) var access: [String: Access] = [:]       // touched only on main

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        reevaluate()
    }

    /// Decide whether the timer should be running right now. Cheap. Call it whenever
    /// settings change, the front app changes, or the Mac wakes up.
    func reevaluate() {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let browser = BrowserWatcher.browsers.first { $0.bundleID == frontID }

        var shouldWatch = false
        if let browser = browser, settings.anythingBlocked, access[browser.bundleID] != .denied {
            if ExtensionBridge.isExtensionConnected(bundleID: browser.bundleID) {
                shouldWatch = false   // the extension handles this browser with zero polling
            } else if browser.family == .safari {
                shouldWatch = true
            } else {
                shouldWatch = settings.automationFallback
            }
        }

        if shouldWatch, let browser = browser {
            current = browser
            if timer == nil {
                let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
                t.tolerance = 0.3
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
            tick()
        } else {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = nil
    }

    /// Forget a "denied" answer so Panda asks macOS again (after the user fixes it in Settings).
    func retryAccess() {
        for key in access.keys where access[key] == .denied { access[key] = .unknown }
        onAccessChanged?()
        reevaluate()
    }

    private func tick() {
        guard let browser = current, !checking else { return }
        // If the extension connected since the last look, hand over to it.
        if browser.family == .chromium, ExtensionBridge.isExtensionConnected(bundleID: browser.bundleID) {
            stop()
            return
        }
        checking = true
        let shared = settings.shared
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = self.readFrontTabs(of: browser)
            DispatchQueue.main.async {
                self.checking = false
                self.handle(result, browser: browser, settings: shared)
            }
        }
    }

    // MARK: Reading tabs (background queue)

    private struct FrontTab {
        let windowID: Int
        let tabIndex: Int
        let tabCount: Int
        let bounds: [Double]
        let url: String
    }

    private enum ReadResult {
        case tabs([FrontTab])
        case denied
        case failed
    }

    private func readSource(for browser: Browser) -> String {
        let tabExpr = browser.family == .safari ? "current tab of w" : "active tab of w"
        let indexExpr = browser.family == .safari ? "index of t" : "active tab index of w"
        return """
        set sep to (character id 9)
        set nl to (character id 10)
        set out to ""
        with timeout of 3 seconds
            tell application id "\(browser.bundleID)"
                repeat with w in (every window)
                    try
                        set t to \(tabExpr)
                        set b to bounds of w
                        set u to URL of t
                        set out to out & (id of w) & sep & (\(indexExpr)) & sep & (count of tabs of w) & sep & (item 1 of b) & sep & (item 2 of b) & sep & (item 3 of b) & sep & (item 4 of b) & sep & u & nl
                    end try
                end repeat
            end tell
        end timeout
        return out
        """
    }

    private func readFrontTabs(of browser: Browser) -> ReadResult {
        let script: NSAppleScript
        if let cached = scripts[browser.bundleID] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: readSource(for: browser)) else { return .failed }
            scripts[browser.bundleID] = created
            script = created
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error = error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: the user said no to "Panda wants to control ...".
            if code == -1743 { return .denied }
            return .failed
        }

        guard let text = descriptor.stringValue else { return .tabs([]) }
        var tabs: [FrontTab] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 8,
                  let windowID = Int(parts[0]),
                  let tabIndex = Int(parts[1]),
                  let tabCount = Int(parts[2]) else { continue }
            let bounds = parts[3...6].compactMap { Double($0) }
            guard bounds.count == 4 else { continue }
            tabs.append(FrontTab(windowID: windowID, tabIndex: tabIndex, tabCount: tabCount, bounds: bounds, url: parts[7]))
        }
        return .tabs(tabs)
    }

    // MARK: Acting on what we read (main queue)

    private func handle(_ result: ReadResult, browser: Browser, settings shared: SharedSettings) {
        switch result {
        case .denied:
            if access[browser.bundleID] != .denied {
                access[browser.bundleID] = .denied
                onAccessChanged?()
            }
            stop()
        case .failed:
            break
        case .tabs(let tabs):
            if access[browser.bundleID] != .allowed {
                access[browser.bundleID] = .allowed
                onAccessChanged?()
            }
            for tab in tabs {
                guard let kind = Rules.verdict(for: tab.url, settings: shared) else { continue }
                let key = "\(browser.bundleID)#\(tab.windowID)#\(tab.tabIndex)"
                guard !closing.contains(key) else { continue }
                closing.insert(key)

                let delay = self.settings.closeDelay
                let anchor = TabGeometry.anchor(
                    family: browser.family,
                    left: tab.bounds[0], top: tab.bounds[1], width: tab.bounds[2] - tab.bounds[0],
                    index: tab.tabIndex - 1, count: tab.tabCount, pinned: 0
                )
                onCaught?(kind, browser.name, anchor, delay)

                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.close(tab, in: browser, kind: kind, key: key)
                }
            }
        }
    }

    private func close(_ tab: FrontTab, in browser: Browser, kind: BlockKind, key: String) {
        let escaped = tab.url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Only close the tab if it is still showing the same address. If the user has
        // already moved on, leave it alone.
        let source = """
        with timeout of 3 seconds
            tell application id "\(browser.bundleID)"
                try
                    set w to window id \(tab.windowID)
                    set t to tab \(tab.tabIndex) of w
                    if (URL of t) is equal to "\(escaped)" then
                        close t
                        return "closed"
                    end if
                end try
            end tell
        end timeout
        return "kept"
        """
        queue.async { [weak self] in
            var closed = false
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                closed = error == nil && result.stringValue == "closed"
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.closing.remove(key)
                if closed { self.onClosed?(kind, browser.name) }
            }
        }
    }
}
