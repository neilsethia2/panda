import AppKit
import Combine
import SwiftUI

/// What the setup screen needs to know about the outside world. Refreshed every couple of
/// seconds, but only while the setup screen is actually open.
final class SetupStatus: ObservableObject {
    @Published var connectedBrowsers: [String] = []
    @Published var installedBrowsers: [ExtensionBridge.ChromiumBrowser] = []
    @Published var safariAccess: BrowserWatcher.Access = .unknown
    @Published var deniedBrowsers: [String] = []
    @Published var needsMove = false

    var accessProvider: (() -> [String: BrowserWatcher.Access])?

    func refresh() {
        connectedBrowsers = ExtensionBridge.connectedBrowserNames
        installedBrowsers = ExtensionBridge.installedChromiumBrowsers
        needsMove = ExtensionBridge.isTranslocated || ExtensionBridge.isRunningFromDiskImage
        let access = accessProvider?() ?? [:]
        safariAccess = access["com.apple.Safari"] ?? .unknown
        deniedBrowsers = BrowserWatcher.browsers
            .filter { access[$0.bundleID] == .denied }
            .map { $0.name }
    }

    /// Fixed values for rendering preview images.
    static func sample() -> SetupStatus {
        let status = SetupStatus()
        status.connectedBrowsers = ["Google Chrome"]
        status.installedBrowsers = [ExtensionBridge.chromiumBrowsers[0]]
        status.safariAccess = .allowed
        return status
    }
}

struct SetupContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var actions: AppActions
    @EnvironmentObject var status: SetupStatus
    @EnvironmentObject var notifier: Notifier

    @State private var copied = false
    @State private var launchAtLogin = LoginItem.isEnabled

    private let ticker = Timer.publish(every: 2, tolerance: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            intro
            if status.needsMove { moveWarning }
            chromeStep
            safariStep
            finishingStep
            privacyNote
        }
        .onAppear {
            status.refresh()
            notifier.refreshPermission()
            launchAtLogin = LoginItem.isEnabled
        }
        .onReceive(ticker) { _ in
            status.refresh()
            notifier.refreshPermission()
        }
    }

    private var intro: some View {
        Card(padding: 18) {
            HStack(spacing: 16) {
                PandaView(mood: .happy, size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Three quick steps")
                        .font(Theme.title(21))
                        .foregroundColor(Theme.ink)
                    Text("Panda lives in your menu bar, at the top right of the screen. He needs a way to see which tab is open in your browser. Set that up once and you're done.")
                        .font(Theme.body(13))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var moveWarning: some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text("!")
                    .font(Theme.number(16))
                    .foregroundColor(Theme.surface)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.ink))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Move Panda to Applications first")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text("Panda is running from the disk image or the Downloads folder. Quit, drag Panda into Applications, and open it from there. The browser link can't be set up until then.")
                        .font(Theme.body(12.5))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var chromeStep: some View {
        let connected = !status.connectedBrowsers.isEmpty
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                StepHeader(
                    number: "1",
                    title: "Add the Panda extension to Chrome",
                    badge: connected ? "Connected: \(status.connectedBrowsers.joined(separator: ", "))" : "Not connected yet",
                    done: connected
                )
                Text("Works the same way in Arc, Brave, Edge and other Chromium browsers. With the extension Panda reacts the instant a tab changes and uses no battery while you browse.")
                    .font(Theme.body(12.5))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 7) {
                    StepLine(index: "a", text: "In Chrome, type chrome://extensions in the address bar and press Return.")
                    StepLine(index: "b", text: "Switch on Developer mode at the top right of that page.")
                    StepLine(index: "c", text: "Click Load unpacked. In the file window press Cmd + Shift + G, paste the folder path, press Return, then click Select.")
                    StepLine(index: "d", text: "Optional: open the extension's Details and allow it in Incognito, so private windows are covered too.")
                }

                HStack(spacing: 8) {
                    Button(copied ? "Copied" : "Copy folder path") {
                        ExtensionBridge.copyExtensionPath()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    Button("Show folder in Finder") { ExtensionBridge.revealExtensionFolder() }
                        .buttonStyle(SoftButtonStyle())
                    if let first = status.installedBrowsers.first {
                        Button("Open \(first.name)") { ExtensionBridge.openExtensionsPage(in: first) }
                            .buttonStyle(SoftButtonStyle())
                    }
                }

                Text("Chrome may show a \"developer mode extensions\" reminder now and then. That is normal for extensions installed this way. Just close it.")
                    .font(Theme.body(11.5))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var safariStep: some View {
        let badge: String
        let done: Bool
        switch status.safariAccess {
        case .allowed:
            badge = "Allowed"
            done = true
        case .denied:
            badge = "Blocked in System Settings"
            done = false
        case .unknown:
            badge = "Asks the first time you use Safari"
            done = false
        }

        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                StepHeader(number: "2", title: "Let Panda see Safari's front tab", badge: badge, done: done)
                Text("Safari has no extension to install. The first time you open Safari with protection on, macOS asks \"Panda wants to control Safari\". Click Allow. Panda only reads the address of the tab in front and closes it when it has to.")
                    .font(Theme.body(12.5))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if !status.deniedBrowsers.isEmpty {
                    Text("Access was refused for \(status.deniedBrowsers.joined(separator: ", ")). Open Automation settings, switch Panda on for that browser, then press Try again.")
                        .font(Theme.body(12.5, weight: .medium))
                        .foregroundColor(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("Open Automation settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                    if !status.deniedBrowsers.isEmpty {
                        Button("Try again") { actions.retryBrowserAccess() }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                    }
                }
            }
        }
    }

    private var finishingStep: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 13) {
                StepHeader(number: "3", title: "Finishing touches", badge: nil, done: false)

                HStack {
                    SiteLabel(
                        title: "Notifications",
                        detail: notifier.permission == .denied
                            ? "Turned off in System Settings. Panda's speech bubble still works."
                            : "A short note each time Panda closes something."
                    )
                    Spacer(minLength: 8)
                    switch notifier.permission {
                    case .allowed:
                        Pill(text: "Allowed", filled: true)
                    case .denied:
                        Button("Open settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(SoftButtonStyle())
                    case .unknown:
                        Button("Allow notifications") { notifier.requestPermission() }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                    }
                }

                Divider().overlay(Theme.line)

                SettingToggle(
                    title: "Open Panda when I log in",
                    detail: "So protection is already on after a restart.",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { value in
                            LoginItem.setEnabled(value)
                            launchAtLogin = LoginItem.isEnabled
                        }
                    )
                )
            }
        }
    }

    private var privacyNote: some View {
        Text("Panda only ever looks at the address of a tab. It never reads pages, takes screenshots or sends anything off this Mac.")
            .font(Theme.body(11.5))
            .foregroundColor(Theme.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

struct StepHeader: View {
    let number: String
    let title: String
    let badge: String?
    let done: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(done ? "✓" : number)
                .font(Theme.number(13))
                .foregroundColor(done ? Theme.surface : Theme.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(done ? Theme.ink : Theme.fill))
            Text(title)
                .font(Theme.body(15, weight: .semibold))
                .foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            if let badge = badge {
                Pill(text: badge, filled: done)
            }
        }
    }
}

struct StepLine: View {
    let index: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(Theme.body(11.5, weight: .semibold))
                .foregroundColor(Theme.muted)
                .frame(width: 14, alignment: .leading)
            Text(text)
                .font(Theme.body(12.5))
                .foregroundColor(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
