import AppKit
import SwiftUI

/// The panes of the main window, listed in the sidebar like System Settings.
enum MainTab: String, CaseIterable, Identifiable {
    case dashboard
    case blocking
    case closer
    case general
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .blocking: return "Blocking"
        case .closer: return "Tab Closer"
        case .general: return "General"
        case .setup: return "Browser Setup"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .blocking: return "hand.raised.fill"
        case .closer: return "pawprint.fill"
        case .general: return "gearshape.fill"
        case .setup: return "puzzlepiece.extension.fill"
        }
    }

    var tint: Color {
        switch self {
        case .dashboard: return Theme.accent
        case .blocking: return Theme.red
        case .closer: return Theme.orange
        case .general: return Theme.grey
        case .setup: return Theme.green
        }
    }
}

final class MainWindowModel: ObservableObject {
    @Published var tab: MainTab = .dashboard
}

/// The one regular window Panda has: a sidebar on the left, the chosen pane on the right.
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
            let size = NSSize(width: MainLayout<EmptyView>.width, height: MainLayout<EmptyView>.height)
            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Panda"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: makeRoot(model))
            w.setContentSize(size)
            w.center()
            w.delegate = self
            window = w
            applyTheme()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Match the window chrome to the current light or dark theme.
    func applyTheme() {
        window?.backgroundColor = Theme.surfaceNS
        window?.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        MainLayout(selection: $model.tab) {
            ScrollView {
                PaneContent(tab: model.tab)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
        }
        .frame(width: MainLayout<EmptyView>.width, height: MainLayout<EmptyView>.height)
        .ignoresSafeArea()
        .preferredColorScheme(Theme.dark ? .dark : .light)
        .id(settings.themeToken)
    }
}

/// Sidebar, pane title and a slot for the pane itself.
struct MainLayout<Content: View>: View {
    @Binding var selection: MainTab
    let content: Content

    static var width: CGFloat { 860 }
    static var height: CGFloat { 620 }
    static var sidebarWidth: CGFloat { 216 }

    init(selection: Binding<MainTab>, @ViewBuilder content: () -> Content) {
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
                .frame(width: MainLayout.sidebarWidth)
            Rectangle()
                .fill(Color.black.opacity(Theme.dark ? 0.5 : 0.10))
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.title)
                    .font(Theme.title(20))
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
        }
    }
}

struct PaneContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .dashboard: DashboardContent()
        case .blocking: SettingsContent(pane: .blocking)
        case .closer: SettingsContent(pane: .closer)
        case .general: SettingsContent(pane: .general)
        case .setup: SetupContent()
        }
    }
}

/// The left-hand list, in the style of System Settings: an identity row on top, then one
/// row per pane with a coloured icon tile.
struct Sidebar: View {
    @Binding var selection: MainTab
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's close and minimise buttons.
            Color.clear.frame(height: 46)

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.card)
                    PandaView(mood: settings.protectionActive ? .happy : .sleeping, size: 34)
                        .offset(y: 1)
                }
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Panda")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text(settings.protectionActive ? "Protection is on" : "Protection is off")
                        .font(Theme.body(11.5))
                        .foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(MainTab.allCases) { tab in
                    SidebarRow(tab: tab, selected: tab == selection)
                        .onTapGesture { selection = tab }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            Toggle(isOn: $settings.master) {
                Text("Protection")
                    .font(Theme.body(13))
                    .foregroundColor(Theme.ink)
            }
            .toggleStyle(PandaToggleStyle())
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
    }

    @ViewBuilder private var sidebarBackground: some View {
        if PreviewRenderer.rendering {
            Theme.sidebarFallback
        } else {
            SidebarMaterial()
        }
    }
}

struct SidebarRow: View {
    let tab: MainTab
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(tab.tint)
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 22, height: 22)

            Text(tab.title)
                .font(Theme.body(13))
                .foregroundColor(selected ? Color.white : Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Theme.accent : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// Heading above a group box.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.body(13, weight: .semibold))
            .foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 4)
    }
}

// MARK: - Dashboard

struct DashboardContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stats: StatsStore

    private var headline: (PandaMood, String, String) {
        let today = stats.today
        if !settings.protectionActive {
            return (.sleeping, "Panda is off duty", "Turn protection on when you want to focus.")
        }
        if today.total == 0 {
            return (.celebrating, "A clean day so far", "Nothing closed yet today. Panda has had nothing to do.")
        }
        if today.total <= 3 {
            return (.happy, "Panda has your back", "A couple of slips, all caught. Keep going.")
        }
        return (.proud, "Busy day for Panda", "\(today.total) attempts today, and every one was closed.")
    }

    var body: some View {
        let today = stats.today
        let headline = self.headline

        return VStack(spacing: 12) {
            Card(padding: 16) {
                HStack(spacing: 14) {
                    PandaView(mood: headline.0, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline.1)
                            .font(Theme.title(18))
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
            HStack(spacing: 10) {
                StatTile(symbol: "camera.fill", tint: Theme.chart1, label: "Instagram", value: "\(today.instagram)", unit: "blocked")
                StatTile(symbol: "play.rectangle.fill", tint: Theme.chart2, label: "YouTube Shorts", value: "\(today.shorts + today.youtube)", unit: "blocked")
                StatTile(symbol: "list.bullet", tint: Theme.chart3, label: "Your blocklist", value: "\(today.custom)", unit: "blocked")
            }
            HStack(spacing: 10) {
                StatTile(symbol: "shield.fill", tint: Theme.green, label: "Distractions prevented", value: "\(today.total)", unit: "today")
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    StatTile(
                        symbol: "clock.fill", tint: Theme.grey, label: "Time protected",
                        value: DurationText.short(stats.protectedSecondsToday(now: context.date)), unit: "today"
                    )
                }
            }

            SectionTitle(text: "Last 7 days")
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daily average")
                                .font(Theme.body(12))
                                .foregroundColor(Theme.muted)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(averageText)
                                    .font(Theme.number(26))
                                    .foregroundColor(Theme.ink)
                                Text("blocked a day")
                                    .font(Theme.body(12))
                                    .foregroundColor(Theme.muted)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(stats.weekTotal) in total")
                                .font(Theme.body(12, weight: .medium))
                                .foregroundColor(Theme.ink)
                            Text("\(DurationText.short(stats.protectedSecondsThisWeek())) protected")
                                .font(Theme.body(12))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    WeekChart(days: stats.lastSevenDays)
                        .frame(height: 150)
                    Divider().overlay(Theme.line)
                    HStack(spacing: 16) {
                        LegendDot(color: Theme.chart1, text: "Instagram  \(stats.weekInstagram)")
                        LegendDot(color: Theme.chart2, text: "YouTube  \(stats.weekShorts)")
                        LegendDot(color: Theme.chart3, text: "Your list  \(stats.weekCustom)")
                        Spacer(minLength: 0)
                    }
                }
            }

            SectionTitle(text: "All time")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ValueRow(title: "Distractions prevented", value: "\(stats.allTimeTotal)")
                    Divider().overlay(Theme.line).padding(.leading, 14)
                    ValueRow(title: "Time with protection on", value: DurationText.short(stats.protectedSecondsAllTime()))
                }
            }

            Text("Everything on this page is stored on this Mac only.")
                .font(Theme.body(11.5))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
    }

    private var averageText: String {
        let average = Double(stats.weekTotal) / 7
        if average == average.rounded() { return "\(Int(average))" }
        return String(format: "%.1f", average)
    }
}

/// A summary tile: coloured symbol and caption on top, the figure underneath.
struct StatTile: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    let unit: String

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                    Text(label)
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundColor(tint)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Theme.number(26))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(Theme.body(12))
                        .foregroundColor(Theme.muted)
                }
            }
        }
    }
}

/// A plain list row: title on the left, value on the right.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.body(13))
                .foregroundColor(Theme.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.body(13))
                .foregroundColor(Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Theme.body(12))
                .foregroundColor(Theme.muted)
        }
    }
}

/// Seven stacked bars with a dashed line at the daily average, as in Screen Time.
struct WeekChart: View {
    let days: [DayEntry]

    var body: some View {
        let peak = max(1, days.map { $0.stats.total }.max() ?? 1)
        let total = days.reduce(0) { $0 + $1.stats.total }
        let average = Double(total) / Double(max(1, days.count))

        return GeometryReader { geo in
            let labelHeight: CGFloat = 20
            let topRoom: CGFloat = 12
            let barArea = max(10, geo.size.height - labelHeight - topRoom)
            let baseline = geo.size.height - labelHeight
            let averageY = baseline - barArea * CGFloat(average) / CGFloat(peak)

            ZStack(alignment: .topLeading) {
                // Baseline
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
                    .offset(y: baseline)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(days) { day in
                        let instagramHeight = barArea * CGFloat(day.stats.instagram) / CGFloat(peak)
                        let youtubeHeight = barArea * CGFloat(day.stats.shorts + day.stats.youtube) / CGFloat(peak)
                        let customHeight = barArea * CGFloat(day.stats.custom) / CGFloat(peak)

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(spacing: 0) {
                                if customHeight > 0 {
                                    Rectangle().fill(Theme.chart3).frame(height: customHeight)
                                }
                                if youtubeHeight > 0 {
                                    Rectangle().fill(Theme.chart2).frame(height: youtubeHeight)
                                }
                                if instagramHeight > 0 {
                                    Rectangle().fill(Theme.chart1).frame(height: instagramHeight)
                                }
                            }
                            .frame(width: 26)
                            .clipShape(TopRounded(radius: 4))
                            Text(day.isToday ? "Today" : day.label)
                                .font(Theme.body(11, weight: day.isToday ? .semibold : .regular))
                                .foregroundColor(day.isToday ? Theme.ink : Theme.muted)
                                .frame(height: labelHeight)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if total > 0 {
                    // Dashed average line with its label at the right-hand end
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: averageY))
                        path.addLine(to: CGPoint(x: geo.size.width - 30, y: averageY))
                    }
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Text("avg")
                        .font(Theme.body(10.5, weight: .medium))
                        .foregroundColor(Theme.green)
                        .frame(width: 26, alignment: .trailing)
                        .offset(x: geo.size.width - 26, y: averageY - 7)
                }
            }
        }
    }
}

/// A rectangle with only its top corners rounded, for the top of a bar.
struct TopRounded: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Settings

struct SettingsContent: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var actions: AppActions
    @EnvironmentObject var characters: CharacterStore

    enum Pane { case blocking, closer, general }
    var pane: Pane

    init(pane: Pane = .blocking) {
        self.pane = pane
    }

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 12) {
            switch pane {
            case .blocking:
                protectionSection
                youtubeSection
                SectionTitle(text: "Your blocklist")
                BlocklistCard()
            case .closer:
                closerSection
                characterSection
            case .general:
                appearanceSection
                generalSection
                dataSection
                HStack {
                    Spacer()
                    Button("Quit Panda") { actions.quit() }
                        .buttonStyle(SoftButtonStyle())
                }
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
                              isOn: $settings.master)
                Divider().overlay(Theme.line)
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
                Divider().overlay(Theme.line)
                SettingToggle(title: "Block YouTube Shorts",
                              detail: "Closes any tab that lands on youtube.com/shorts.",
                              isOn: $settings.shorts)
                    .opacity(settings.youtube ? 1 : 0.45)
                Divider().overlay(Theme.line)
                SettingToggle(title: "Allow normal YouTube videos",
                              detail: "Keep this on so lectures and tutorials are never touched. Turn it off to close all of YouTube.",
                              isOn: $settings.allowNormalVideos)
                    .opacity(settings.youtube ? 1 : 0.45)
            }
        }
    }

    private var entryOptions: [(EntrySide, String)] {
        var options: [(EntrySide, String)] = [
            (.left, EntrySide.left.title),
            (.right, EntrySide.right.title),
            (.nearest, EntrySide.nearest.title),
            (.top, EntrySide.top.title),
        ]
        if settings.companionMode == .always {
            options.append((.home, EntrySide.home.title))
        }
        return options
    }

    @ViewBuilder private var closerSection: some View {
        let hidden = settings.companionMode == .menuBarOnly

        SectionTitle(text: "The tab closer")
        Card {
            VStack(alignment: .leading, spacing: 13) {
                OptionRow(title: "When he is on screen",
                          detail: "Only when he closes something: he runs in, shuts the tab and leaves, like in the video. Always: he also rests in a corner between catches.") {
                    ChoiceChips(options: CompanionMode.allCases.map { ($0, $0.title) }, selection: $settings.companionMode)
                }
                Divider().overlay(Theme.line)
                Group {
                    OptionRow(title: "Where he comes in from",
                              detail: "He runs straight along the tab bar from this side and leaves the same way.") {
                        ChoiceChips(options: entryOptions, selection: $settings.entrySide)
                    }
                    Divider().overlay(Theme.line)
                    OptionRow(title: "Size", detail: nil) {
                        ChoiceChips(options: CompanionSize.allCases.map { ($0, $0.title) }, selection: $settings.companionSize)
                    }
                    Divider().overlay(Theme.line)
                    SettingToggle(title: "He runs to the tab and closes it",
                                  detail: "The run takes about half a second. Turn this off to close tabs the instant they open.",
                                  isOn: $settings.walkToTab)
                    Divider().overlay(Theme.line)
                    SettingToggle(title: "Show a message when a tab is closed",
                                  detail: "The speech bubble next to him, such as \"Not today! Get back to work.\"",
                                  isOn: $settings.showBubble)
                    Divider().overlay(Theme.line)
                    HStack {
                        SiteLabel(title: "See it in action", detail: "Plays one run across the top of your screen with the settings above.")
                        Spacer(minLength: 8)
                        if settings.companionMode == .always {
                            Button("Reset resting spot") { actions.resetCompanion() }
                                .buttonStyle(SoftButtonStyle())
                        }
                        Button("Preview") { actions.demoCompanion() }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                    }
                }
                .opacity(hidden ? 0.4 : 1)
                .allowsHitTesting(!hidden)
            }
        }
    }

    @ViewBuilder private var characterSection: some View {
        SectionTitle(text: "Character")
        Card {
            VStack(alignment: .leading, spacing: 13) {
                OptionRow(title: "Who closes your tabs",
                          detail: "Pick a built-in character, or use any picture of your own. Your picture is cut out and given the same run: it hops, rocks and leans as it moves.") {
                    HStack(spacing: 14) {
                        ChoiceChips(
                            options: [
                                (CharacterStyle.panda, "Panda"),
                                (CharacterStyle.ghost, "Ghost"),
                                (CharacterStyle.custom, "My own picture"),
                            ],
                            selection: $settings.characterStyle
                        )
                        Spacer(minLength: 0)
                        if settings.characterStyle != .custom {
                            CharacterView(image: nil, style: settings.characterStyle, mood: .happy, size: 46)
                        }
                    }
                }

                if settings.characterStyle == .custom {
                    Divider().overlay(Theme.line)
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.surface)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                            if let image = characters.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(8)
                            } else {
                                Text("No picture")
                                    .font(Theme.label(9.5))
                                    .foregroundColor(Theme.muted)
                            }
                        }
                        .frame(width: 76, height: 76)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(characters.working ? "Working on it…" : (characters.note ?? (characters.hasImage ? "Your character is ready." : "Pick a picture with one clear subject. A PNG with a transparent background works best.")))
                                .font(Theme.body(12))
                                .foregroundColor(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button(characters.hasImage ? "Choose another picture" : "Choose a picture") {
                                    characters.chooseImage(removeBackground: settings.removeImageBackground) { _ in }
                                }
                                .buttonStyle(SoftButtonStyle(prominent: true))
                                .disabled(characters.working)
                                if characters.hasImage {
                                    Button("Remove") {
                                        characters.remove()
                                        settings.characterStyle = .panda
                                    }
                                    .buttonStyle(SoftButtonStyle())
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(Theme.line)
                    SettingToggle(title: "Cut the subject out of its background",
                                  detail: "Applies to the next picture you choose. Needs macOS 14 or later.",
                                  isOn: $settings.removeImageBackground)
                    Divider().overlay(Theme.line)
                    SettingToggle(title: "Mirror the picture when it runs left",
                                  detail: "Turn this off if your picture has writing on it or should never be flipped.",
                                  isOn: $settings.flipWhenWalkingLeft)
                }
            }
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        SectionTitle(text: "Appearance")
        Card {
            OptionRow(title: "Theme", detail: nil) {
                ChoiceChips(options: AppearanceMode.allCases.map { ($0, $0.title) }, selection: $settings.appearance)
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
                Divider().overlay(Theme.line)
                SettingToggle(title: "Notifications",
                              detail: "A macOS notification each time something is closed. Separate from the speech bubble.",
                              isOn: $settings.notifications)
                Divider().overlay(Theme.line)
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

/// A titled setting whose control sits underneath the text.
struct OptionRow<Control: View>: View {
    let title: String
    let detail: String?
    let control: Control

    init(title: String, detail: String?, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.ink)
                if let detail = detail {
                    Text(detail)
                        .font(Theme.body(11.5))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Paste a link, and Panda closes that site too.
struct BlocklistCard: View {
    @EnvironmentObject var settings: AppSettings

    @State private var text = ""
    @State private var wholeSite = true
    @State private var feedback: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                SettingToggle(title: "Block the sites on my list",
                              detail: "Anything you add here is closed the same way as Instagram.",
                              isOn: $settings.customOn)
                Divider().overlay(Theme.line)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        field
                        Button("Add") { add(text) }
                            .buttonStyle(SoftButtonStyle(prominent: true))
                        Button("Paste from clipboard") {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                add(pasted)
                            } else {
                                feedback = "There is no link on the clipboard."
                            }
                        }
                        .buttonStyle(SoftButtonStyle())
                    }
                    HStack(spacing: 10) {
                        ChoiceChips(options: [(true, "Block the whole site"), (false, "Only this exact link")], selection: $wholeSite)
                        if let feedback = feedback {
                            Text(feedback)
                                .font(Theme.body(11.5))
                                .foregroundColor(Theme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !settings.customSites.isEmpty {
                    Divider().overlay(Theme.line)
                    VStack(spacing: 0) {
                        ForEach(settings.customSites, id: \.self) { entry in
                            HStack(spacing: 10) {
                                Text(entry)
                                    .font(Theme.body(13))
                                    .foregroundColor(Theme.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(entry.contains("/") || entry.contains("?") ? "This link" : "Whole site")
                                    .font(Theme.body(11))
                                    .foregroundColor(Theme.muted)
                                Spacer(minLength: 8)
                                Button("Remove") { settings.removeCustomSite(entry) }
                                    .buttonStyle(SoftButtonStyle())
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .opacity(settings.customOn ? 1 : 0.45)
                }
            }
        }
    }

    @ViewBuilder private var field: some View {
        if PreviewRenderer.rendering {
            // The system text field cannot be drawn off-screen, so previews show a stand-in.
            Text("Paste a link, for example reddit.com")
                .font(Theme.body(13))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
        } else {
            TextField("Paste a link, for example reddit.com", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.body(13))
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line, lineWidth: 1))
                .onSubmit { add(text) }
        }
    }

    private func add(_ raw: String) {
        switch settings.addCustomSite(raw, wholeSite: wholeSite) {
        case .added(let entry):
            feedback = "Added \(entry)."
            text = ""
        case .duplicate(let entry):
            feedback = "\(entry) is already on the list."
            text = ""
        case .invalid:
            feedback = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Paste or type a link first."
                : "That doesn't look like a web address."
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
                    .font(Theme.body(13))
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
