import SwiftUI

/// The panel that opens from the menu bar panda.
struct PopoverView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var actions: AppActions

    private var mood: PandaMood {
        if !settings.protectionActive { return .sleeping }
        return .happy
    }

    private var shortsBinding: Binding<Bool> {
        Binding(
            get: { settings.youtube && settings.shorts },
            set: { on in
                if on { settings.youtube = true }
                settings.shorts = on
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            masterCard
            sitesCard
            todayCard
            footer
        }
        .padding(16)
        .frame(width: StatusItemController.popoverSize.width, height: StatusItemController.popoverSize.height, alignment: .top)
        .background(SurfaceBackground())
        .preferredColorScheme(Theme.dark ? .dark : .light)
        .id(settings.themeToken)
    }

    private var header: some View {
        HStack(spacing: 12) {
            PandaView(mood: mood, size: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text("Panda")
                    .font(Theme.title(22))
                    .foregroundColor(Theme.ink)
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.protectionActive ? Theme.ink : Color.clear)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: 1.2))
                        .frame(width: 7, height: 7)
                    Text(settings.protectionActive ? "Protection ON" : "Protection OFF")
                        .font(Theme.body(13, weight: .medium))
                        .foregroundColor(Theme.ink)
                }
                Text(settings.protectionActive ? "Your little productivity companion" : "Panda is napping")
                    .font(Theme.body(11.5))
                    .foregroundColor(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var masterCard: some View {
        Card(padding: 14) {
            Toggle(isOn: $settings.master) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Master protection")
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text(settings.master ? "Panda is on watch" : "Everything is allowed")
                        .font(Theme.body(11.5))
                        .foregroundColor(Theme.muted)
                }
            }
            .toggleStyle(PandaToggleStyle(large: true))
        }
    }

    private var sitesCard: some View {
        Card(padding: 14) {
            VStack(spacing: 11) {
                Toggle(isOn: $settings.instagram) {
                    SiteLabel(
                        title: "Instagram",
                        detail: settings.instagram ? "Blocking ON" : "Allowed"
                    )
                }
                .toggleStyle(PandaToggleStyle())

                Divider().overlay(Theme.line)

                Toggle(isOn: shortsBinding) {
                    SiteLabel(
                        title: "YouTube Shorts",
                        detail: (settings.youtube && settings.shorts) ? "Blocking ON" : "Allowed"
                    )
                }
                .toggleStyle(PandaToggleStyle())

                Divider().overlay(Theme.line)

                HStack {
                    SiteLabel(title: "Normal videos", detail: "Lectures and tutorials stay open")
                    Spacer(minLength: 8)
                    Pill(text: (settings.youtube && !settings.allowNormalVideos) ? "Blocked" : "Allowed")
                }

                Divider().overlay(Theme.line)

                if settings.customSites.isEmpty {
                    HStack {
                        SiteLabel(title: "Your blocklist", detail: "Paste any link to block it too")
                        Spacer(minLength: 8)
                        Button("Add a site") { actions.openBlocklist() }
                            .buttonStyle(SoftButtonStyle())
                    }
                } else {
                    Toggle(isOn: $settings.customOn) {
                        HStack(spacing: 8) {
                            SiteLabel(
                                title: "Your blocklist",
                                detail: settings.customSites.count == 1 ? "1 site" : "\(settings.customSites.count) sites"
                            )
                            Button("Edit") { actions.openBlocklist() }
                                .buttonStyle(SoftButtonStyle())
                        }
                    }
                    .toggleStyle(PandaToggleStyle())
                }
            }
            .opacity(settings.master ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.2), value: settings.master)
        }
    }

    private var todayCard: some View {
        let today = stats.today
        return Card(padding: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(today.total)")
                    .font(Theme.number(34))
                    .foregroundColor(Theme.ink)
                    .frame(minWidth: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.total == 1 ? "distraction blocked today" : "distractions blocked today")
                        .font(Theme.body(12.5, weight: .medium))
                        .foregroundColor(Theme.ink)
                    Text(today.custom > 0
                         ? "\(today.instagram) Instagram  ·  \(today.shorts + today.youtube) YouTube  ·  \(today.custom) other"
                         : "\(today.instagram) Instagram  ·  \(today.shorts + today.youtube) YouTube")
                        .font(Theme.body(11.5))
                        .foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Dashboard") { actions.openDashboard() }
                .buttonStyle(SoftButtonStyle(prominent: true))
            Button("Settings") { actions.openSettings() }
                .buttonStyle(SoftButtonStyle())
            Spacer(minLength: 0)
            Button("Quit") { actions.quit() }
                .buttonStyle(SoftButtonStyle())
        }
        .padding(.top, 2)
    }
}

struct SiteLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(title)
                .font(Theme.body(13.5, weight: .medium))
                .foregroundColor(Theme.ink)
            Text(detail)
                .font(Theme.body(11.5))
                .foregroundColor(Theme.muted)
        }
    }
}
