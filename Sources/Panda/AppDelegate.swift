import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let stats = StatsStore.shared
    private let actions = AppActions()
    private let setupStatus = SetupStatus()

    private var companion: CompanionController?
    private var coordinator: BlockCoordinator?
    private var statusController: StatusItemController?
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Developer aid: `Panda --render-previews <folder>` writes PNGs of every screen and exits.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-previews") {
            let folder = arguments.count > flag + 1 ? arguments[flag + 1] : "previews"
            PreviewRenderer.renderAll(to: URL(fileURLWithPath: folder))
            exit(0)
        }

        // Only one Panda at a time.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: PandaPaths.bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        ExtensionBridge.install()
        Notifier.shared.start()

        Theme.dark = resolvedDark()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemThemeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        let companion = CompanionController(settings: settings)
        let coordinator = BlockCoordinator(settings: settings, stats: stats, companion: companion)
        let statusController = StatusItemController(settings: settings, stats: stats, actions: actions)

        let mainWindow = MainWindowController { [settings = self.settings, stats = self.stats, actions = self.actions, setupStatus = self.setupStatus] model in
            AnyView(
                MainView(model: model)
                    .environmentObject(settings)
                    .environmentObject(stats)
                    .environmentObject(actions)
                    .environmentObject(setupStatus)
                    .environmentObject(Notifier.shared)
                    .environmentObject(CharacterStore.shared)
            )
        }

        self.companion = companion
        self.coordinator = coordinator
        self.statusController = statusController
        self.mainWindow = mainWindow

        setupStatus.accessProvider = { [weak coordinator] in coordinator?.watcher.access ?? [:] }

        actions.openDashboard = { [weak self] in self?.open(.dashboard) }
        actions.openSettings = { [weak self] in self?.open(.blocking) }
        actions.openSetup = { [weak self] in self?.open(.setup) }
        actions.closePopover = { [weak statusController] in statusController?.closePopover() }
        actions.openBlocklist = { [weak self] in self?.open(.blocking) }
        actions.resetCompanion = { [weak companion] in companion?.resetHome() }
        actions.demoCompanion = { [weak companion] in companion?.demo() }
        actions.retryBrowserAccess = { [weak coordinator] in coordinator?.watcher.retryAccess() }
        actions.quit = { NSApp.terminate(nil) }

        coordinator.onStateChanged = { [weak statusController, weak setupStatus] in
            statusController?.refreshIcon()
            setupStatus?.refresh()
        }
        settings.onChange = { [weak self, weak coordinator] in
            self?.applyTheme()
            coordinator?.settingsChanged()
        }
        coordinator.settingsChanged()

        if !settings.hasOnboarded {
            settings.hasOnboarded = true
            open(.setup)
            // Ask for notification permission once, right at the start, with the setup screen
            // on screen to explain why.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                Notifier.shared.requestPermission()
            }
        }
    }

    // MARK: Light and dark

    private func resolvedDark() -> Bool {
        switch settings.appearance {
        case .light: return false
        case .dark: return true
        case .system: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
    }

    private func applyTheme() {
        let dark = resolvedDark()
        guard dark != Theme.dark else { return }
        Theme.dark = dark
        statusController?.applyTheme()
        mainWindow?.applyTheme()
        settings.themeToken += 1
    }

    @objc private func systemThemeChanged() {
        // The system setting lands a moment after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.applyTheme()
        }
    }

    private func open(_ tab: MainTab) {
        statusController?.closePopover()
        mainWindow?.show(tab: tab)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Panda again from Applications or Spotlight shows the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        open(.dashboard)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
