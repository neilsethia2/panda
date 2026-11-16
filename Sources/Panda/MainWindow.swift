import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case settings = "Settings"
    case setup = "Setup"

    var id: String { rawValue }
}

final class MainWindowModel: ObservableObject {
    @Published var tab: MainTab = .dashboard
}

/// The one regular window Panda has: dashboard, settings and setup, behind three tabs.
final class MainWindowController: NSObject, NSWindowDelegate {
    let model = MainWindowModel()
    private var window: NSWindow?
    private let makeRoot: (MainWindowModel) -> AnyView

    init(makeRoot: @escaping (MainWindowModel) -> AnyView) {
        self.makeRoot = makeRoot
        super.init()
    }

    func show(tab: MainTab) {
        model.tab = tab
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Panda"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(red: 0.984, green: 0.965, blue: 0.925, alpha: 1)
            w.appearance = NSAppearance(named: .aqua)
            w.contentViewController = NSHostingController(rootView: makeRoot(model))
            w.setContentSize(NSSize(width: 760, height: 640))
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PandaView(mood: settings.protectionActive ? .happy : .sleeping, size: 40)
                Text("Panda")
                    .font(Theme.title(20))
                    .foregroundColor(Theme.ink)
                Spacer()
                TabBar(selection: $model.tab)
            }
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 14)

            ScrollView {
                Group {
                    switch model.tab {
                    case .dashboard: DashboardContent()
                    case .settings: SettingsContent()
                    case .setup: SetupContent()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .padding(.top, 6)
            }
        }
        .frame(width: 760, height: 640)
        .background(Theme.cream)
        .preferredColorScheme(.light)
    }
}

/// Segmented control drawn in SwiftUI.
struct TabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                Text(tab.rawValue)
                    .font(Theme.body(12.5, weight: .semibold))
                    .foregroundColor(selection == tab ? Theme.cream : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6.5)
                    .background(Capsule().fill(selection == tab ? Theme.ink : Color.clear))
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
                    }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.creamDeep))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .tracking(0.6)
            .font(Theme.body(12, weight: .bold))
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }
}

// MARK: - Dashboard

struct DashboardContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stats: StatsStore

    private var headline: (PandaMood, String, String) {
        let today = stats.today
        if !settings.protectionActive {
            return (.sleeping, "Panda is off duty", "Turn protection on from the menu bar when you want to focus.")
        }
        if today.total == 0 {
            return (.celebrating, "A clean day so far", "No Instagram, no Shorts. Panda is very proud of you.")
        }
        if today.total <= 3 {
            return (.happy, "Panda has your back", "A couple of slips, all caught. Keep going.")
        }
        return (.proud, "Busy day for Panda", "\(today.total) attempts today, and every one was closed.")
    }

    var body: some View {
        let today = stats.today
        let headline = self.headline

        return VStack(spacing: 16) {
            Card(padding: 18) {
                HStack(spacing: 16) {
                    PandaView(mood: headline.0, size: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline.1)
                            .font(Theme.title(21))
                            .foregroundColor(Theme.ink)
                        Text(headline.2)
                            .font(Theme.body(13))
                            .foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            SectionTitle(text: "Today")
            HStack(spacing: 12) {
                StatTile(value: "\(today.instagram)", label: "Instagram attempts blocked")
                StatTile(value: "\(today.shorts)", label: "YouTube Shorts blocked")
                StatTile(value: "\(today.total)", label: "Distractions prevented")
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    StatTile(
                        value: DurationText.short(stats.protectedSecondsToday(now: context.date)),
                        label: "Time protected"
                    )
                }
            }

            SectionTitle(text: "This week")
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(stats.weekTotal) blocked in the last 7 days")
                                .font(Theme.body(15, weight: .bold))
                                .foregroundColor(Theme.ink)
                            Text("\(stats.weekInstagram) Instagram  ·  \(stats.weekShorts) YouTube  ·  \(DurationText.short(stats.protectedSecondsThisWeek())) protected")
                                .font(Theme.body(12))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            LegendDot(color: Theme.ink, text: "Instagram")
                            LegendDot(color: Theme.gold, text: "YouTube")
                        }
                    }
                    WeekChart(days: stats.lastSevenDays)
                        .frame(height: 150)
                }
            }

            SectionTitle(text: "All time")
            HStack(spacing: 12) {
                StatTile(value: "\(stats.allTimeTotal)", label: "Total distractions prevented")
                StatTile(value: DurationText.short(stats.protectedSecondsAllTime()), label: "Total time with protection on")
            }

            Text("Everything on this page is stored on this Mac only.")
                .font(Theme.body(11.5))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(Theme.body(11.5))
                    .foregroundColor(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28, alignment: .topLeading)
            }
        }
    }
}

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(Theme.body(11.5))
                .foregroundColor(Theme.muted)
        }
    }
}

/// Seven stacked bars, one per day. Plain SwiftUI shapes.
struct WeekChart: View {
    let days: [DayEntry]

    var body: some View {
        let peak = max(1, days.map { $0.stats.total }.max() ?? 1)

        return GeometryReader { geo in
            let labelHeight: CGFloat = 20
            let valueHeight: CGFloat = 18
            let barArea = max(10, geo.size.height - labelHeight - valueHeight)

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(days) { day in
                    let instagramHeight = barArea * CGFloat(day.stats.instagram) / CGFloat(peak)
                    let youtubeHeight = barArea * CGFloat(day.stats.shorts + day.stats.youtube) / CGFloat(peak)

                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(day.stats.total > 0 ? "\(day.stats.total)" : " ")
                            .font(Theme.body(11, weight: .semibold))
                            .foregroundColor(Theme.ink)
                            .frame(height: valueHeight - 4)
                        if day.stats.total == 0 {
                            Capsule()
                                .fill(Theme.creamDeep)
                                .frame(height: 5)
                        } else {
                            VStack(spacing: 2) {
                                if youtubeHeight > 0 {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Theme.gold)
                                        .frame(height: max(4, youtubeHeight - 1))
                                }
                                if instagramHeight > 0 {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Theme.ink)
                                        .frame(height: max(4, instagramHeight - 1))
                                }
                            }
                        }
                        Text(day.isToday ? "Today" : day.label)
                            .font(Theme.body(11, weight: day.isToday ? .bold : .regular))
                            .foregroundColor(day.isToday ? Theme.ink : Theme.muted)
                            .frame(height: labelHeight - 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var actions: AppActions

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 16) {
            protectionSection
            youtubeSection
            pandaSection
            generalSection
            dataSection
            HStack {
                Spacer()
                Button("Quit Panda completely") { actions.quit() }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    @ViewBuilder private var protectionSection: some View {
        SectionTitle(text: "Protection")
        Card {
            VStack(spacing: 13) {
                SettingToggle(title: "Master protection",
                              detail: "When this is off, nothing is blocked at all.",
                              isOn: $settings.master, large: true)
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Instagram protection",
                              detail: "Closes any instagram.com tab the moment it opens.",
                              isOn: $settings.instagram)
            }
        }
    }

    @ViewBuilder private var youtubeSection: some View {
        SectionTitle(text: "YouTube")
        Card {
            VStack(spacing: 13) {
                SettingToggle(title: "YouTube protection",
                              detail: "Turns Panda's YouTube rules on or off as a group.",
                              isOn: $settings.youtube)
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Block YouTube Shorts",
                              detail: "Closes any tab that lands on youtube.com/shorts.",
                              isOn: $settings.shorts)
                    .opacity(settings.youtube ? 1 : 0.45)
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Allow normal YouTube videos",
                              detail: "Keep this on so lectures and tutorials are never touched. Turn it off to close all of YouTube.",
                              isOn: $settings.allowNormalVideos)
                    .opacity(settings.youtube ? 1 : 0.45)
            }
        }
    }

    @ViewBuilder private var pandaSection: some View {
        SectionTitle(text: "Panda")
        Card {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where Panda lives")
                        .font(Theme.body(13.5, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    HStack(spacing: 6) {
                        ForEach(CompanionMode.allCases) { mode in
                            Text(mode.title)
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundColor(settings.companionMode == mode ? Theme.cream : Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6.5)
                                .background(Capsule().fill(settings.companionMode == mode ? Theme.ink : Theme.creamDeep))
                                .contentShape(Capsule())
                                .onTapGesture { settings.companionMode = mode }
                        }
                    }
                }
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Panda runs to the tab and closes it",
                              detail: "He takes about half a second to get there. Turn this off to close tabs instantly.",
                              isOn: $settings.walkToTab)
                    .opacity(settings.companionMode == .menuBarOnly ? 0.45 : 1)
                Divider().overlay(Theme.creamLine)
                HStack {
                    SiteLabel(title: "Panda's corner", detail: "Drag him anywhere on screen. This sends him back to the bottom right.")
                    Spacer(minLength: 8)
                    Button("Reset position") { actions.resetCompanion() }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private var generalSection: some View {
        SectionTitle(text: "General")
        Card {
            VStack(spacing: 13) {
                SettingToggle(title: "Open Panda when I log in",
                              detail: "Protection starts by itself after a restart.",
                              isOn: Binding(
                                get: { launchAtLogin },
                                set: { value in
                                    LoginItem.setEnabled(value)
                                    launchAtLogin = LoginItem.isEnabled
                                }
                              ))
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Notifications",
                              detail: "A short note each time Panda closes something.",
                              isOn: $settings.notifications)
                Divider().overlay(Theme.creamLine)
                SettingToggle(title: "Guard browsers that don't have the extension",
                              detail: "Uses macOS Automation to check the front tab once a second, only while that browser is in front. Safari always works this way.",
                              isOn: $settings.automationFallback)
            }
        }
    }

    @ViewBuilder private var dataSection: some View {
        SectionTitle(text: "Data")
        Card {
            HStack {
                SiteLabel(title: "Statistics", detail: "Stored only on this Mac, in Application Support/Panda.")
                Spacer(minLength: 8)
                if confirmReset {
                    Button("Really erase") {
                        stats.reset()
                        confirmReset = false
                    }
                    .buttonStyle(SoftButtonStyle(prominent: true))
                    Button("Cancel") { confirmReset = false }
                        .buttonStyle(SoftButtonStyle())
                } else {
                    Button("Erase statistics") { confirmReset = true }
                        .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }
}

struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var large: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(13.5, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(detail)
                    .font(Theme.body(11.5))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(PandaToggleStyle(large: large))
    }
}
