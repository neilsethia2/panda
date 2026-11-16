import AppKit
import SwiftUI

/// Renders the app's screens to PNG files without showing any windows.
/// Used by the build pipeline so the design can be checked on every build.
@MainActor
enum PreviewRenderer {
    static func renderAll(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings.shared
        let stats = StatsStore.sample()
        let actions = AppActions()
        let status = SetupStatus.sample()
        let notifier = Notifier.shared

        func themed<V: View>(_ view: V) -> some View {
            view
                .environmentObject(settings)
                .environmentObject(stats)
                .environmentObject(actions)
                .environmentObject(status)
                .environmentObject(notifier)
                .environment(\.colorScheme, .light)
        }

        // Every mood, side by side
        let moods = HStack(spacing: 18) {
            ForEach(PandaMood.allCases, id: \.self) { mood in
                VStack(spacing: 8) {
                    PandaView(mood: mood, size: 120)
                    Text(mood.rawValue)
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(28)
        .background(Theme.cream)
        save(themed(moods), to: folder.appendingPathComponent("moods.png"))

        save(themed(PopoverView()), to: folder.appendingPathComponent("popover.png"))

        let page: (String, AnyView) -> AnyView = { title, content in
            AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(Theme.title(20))
                        .foregroundColor(Theme.ink)
                    content
                }
                .padding(28)
                .frame(width: 760)
                .background(Theme.cream)
            )
        }
        save(themed(page("Dashboard", AnyView(DashboardContent()))), to: folder.appendingPathComponent("dashboard.png"))
        save(themed(page("Settings", AnyView(SettingsContent()))), to: folder.appendingPathComponent("settings.png"))
        save(themed(page("Setup", AnyView(SetupContent()))), to: folder.appendingPathComponent("setup.png"))

        // The floating companion with a speech bubble
        let model = CompanionModel()
        model.mood = .proud
        model.bubble = "Not today! Get back to work."
        model.bubbleOnLeft = true
        let companion = CompanionView(model: model)
            .padding(20)
            .background(Color(white: 0.55))
        save(themed(companion), to: folder.appendingPathComponent("companion.png"))

        // Menu bar icons, enlarged
        for (name, awake) in [("menubar-on", true), ("menubar-off", false)] {
            let icon = StatusItemController.icon(awake: awake)
            let big = NSImage(size: NSSize(width: 144, height: 144))
            big.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 144, height: 144).fill()
            icon.draw(in: NSRect(x: 0, y: 0, width: 144, height: 144))
            big.unlockFocus()
            write(big, to: folder.appendingPathComponent("\(name).png"))
        }
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            FileHandle.standardError.write("could not render \(url.lastPathComponent)\n".data(using: .utf8) ?? Data())
            return
        }
        write(image, to: url)
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
