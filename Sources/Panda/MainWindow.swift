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
            w.contentViewController = NSHostingController(rootView: makeRoot(model))
            w.setContentSize(NSSize(width: 760, height: 640))
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
        .background(SurfaceBackground())
        .preferredColorScheme(Theme.dark ? .dark : .light)
        .id(settings.themeToken)
    }
}

/// Segmented control drawn in SwiftUI.
struct TabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                Text(tab.rawValue)
                    .font(Theme.body(12.5, weight: .medium))
                    .foregroundColor(selection == tab ? Theme.surface : Theme.ink)
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
        .background(Capsule().fill(Theme.fill))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .tracking(1.4)
            .font(Theme.label(10.5))
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
            HStack(spacing: 10) {
                StatTile(value: "\(today.instagram)", label: "Instagram attempts blocked")
                StatTile(value: "\(today.shorts + today.youtube)", label: "YouTube Shorts blocked")
                StatTile(value: "\(today.custom)", label: "From your own blocklist")
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
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Text("\(stats.weekInstagram) Instagram  ·  \(stats.weekShorts) YouTube  ·  \(stats.weekCustom) your list  ·  \(DurationText.short(stats.protectedSecondsThisWeek())) protected")
                                .font(Theme.body(12))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            LegendDot(color: Theme.ink, text: "Instagram")
                            LegendDot(color: Theme.series2, text: "YouTube")
                            LegendDot(color: Theme.series3, text: "Your list")
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
                    .font(Theme.number(26))
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
                    let customHeight = barArea * CGFloat(day.stats.custom) / CGFloat(peak)

                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(day.stats.total > 0 ? "\(day.stats.total)" : " ")
                            .font(Theme.body(11, weight: .medium))
                            .foregroundColor(Theme.ink)
                            .frame(height: valueHeight - 4)
                        if day.stats.total == 0 {
                            Capsule()
                                .fill(Theme.fill)
                                .frame(height: 5)
                        } else {
                            VStack(spacing: 2) {
                                if customHeight > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.series3)
                                        .frame(height: max(4, customHeight - 1))
                                }
                                if youtubeHeight > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.series2)
                                        .frame(height: max(4, youtubeHeight - 1))
                                }
                                if instagramHeight > 0 {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
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
    @EnvironmentObject var characters: CharacterStore

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 16) {
            protectionSection
            youtubeSection
            SectionTitle(text: "Your blocklist")
            BlocklistCard()
            closerSection
            characterSection
            appearanceSection
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
                    .font(Theme.body(13.5, weight: .medium))
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
                                    .font(Theme.label(12))
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
                    .font(Theme.body(13.5, weight: .medium))
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
