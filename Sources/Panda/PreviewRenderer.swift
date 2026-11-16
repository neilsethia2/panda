import AppKit
import SwiftUI

/// Renders the app's screens to PNG files without showing any windows.
/// Used by the build pipeline so the design can be checked on every build.
@MainActor
enum PreviewRenderer {
    /// True while preview images are being drawn. A few system controls cannot be drawn
    /// off-screen, so views show a stand-in for them when this is set.
    static var rendering = false

    static func renderAll(to folder: URL) {
        rendering = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let settings = AppSettings.shared
        let stats = StatsStore.sample()
        let actions = AppActions()
        let status = SetupStatus.sample()
        let notifier = Notifier.shared
        let characters = CharacterStore.shared

        func themed<V: View>(_ view: V) -> some View {
            view
                .environmentObject(settings)
                .environmentObject(stats)
                .environmentObject(actions)
                .environmentObject(status)
                .environmentObject(notifier)
                .environmentObject(characters)
                .environment(\.colorScheme, Theme.dark ? .dark : .light)
        }

        func page(_ title: String, _ content: AnyView) -> AnyView {
            AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(Theme.title(20))
                        .foregroundColor(Theme.ink)
                    content
                }
                .padding(28)
                .frame(width: 760)
                .background(SurfaceBackground())
            )
        }

        // Sample blocklist so the list is visible in the pictures. Nothing is saved:
        // the real settings are put back before returning.
        let savedSites = settings.customSites
        let savedMode = settings.companionMode
        let savedStyle = settings.characterStyle
        settings.onChange = nil
        settings.customSites = ["reddit.com", "x.com", "youtube.com/@somechannel"]

        for dark in [false, true] {
            Theme.dark = dark
            let suffix = dark ? "-dark" : ""
            save(themed(PopoverView()), to: folder.appendingPathComponent("popover\(suffix).png"))
            save(themed(page("Dashboard", AnyView(DashboardContent()))), to: folder.appendingPathComponent("dashboard\(suffix).png"))
            settings.characterStyle = .panda
            settings.companionMode = .onCatch
            save(themed(page("Settings", AnyView(SettingsContent()))), to: folder.appendingPathComponent("settings\(suffix).png"))
        }
        Theme.dark = false
        save(themed(page("Setup", AnyView(SetupContent()))), to: folder.appendingPathComponent("setup.png"))

        // Every mood, side by side
        let moods = HStack(spacing: 18) {
            ForEach(PandaMood.allCases, id: \.self) { mood in
                VStack(spacing: 8) {
                    PandaView(mood: mood, size: 120)
                    Text(mood.rawValue)
                        .font(Theme.label(10.5))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(28)
        .background(SurfaceBackground())
        save(themed(moods), to: folder.appendingPathComponent("moods.png"))

        // The run cycle, frame by frame, as it plays over a dark browser tab bar
        let phases: [Double] = (0..<8).map { Double($0) / 8 * 2 * Double.pi }
        let run = HStack(spacing: 6) {
            ForEach(phases, id: \.self) { phase in
                CharacterView(image: nil, mood: .suspicious, size: 96).figure(phase: phase)
                    .frame(width: 112, height: 120, alignment: .bottom)
            }
        }
        .padding(20)
        .background(Color(white: 0.16))
        save(themed(run), to: folder.appendingPathComponent("run-cycle.png"))

        // The second built-in character: every mood, then his run
        let ghostMoods = HStack(spacing: 18) {
            ForEach(PandaMood.allCases, id: \.self) { mood in
                VStack(spacing: 8) {
                    CharacterView(image: nil, style: .ghost, mood: mood, size: 120)
                    Text(mood.rawValue)
                        .font(Theme.label(10.5))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(28)
        .background(SurfaceBackground())
        save(themed(ghostMoods), to: folder.appendingPathComponent("ghost-moods.png"))

        let ghostRun = HStack(spacing: 6) {
            ForEach(phases, id: \.self) { phase in
                CharacterView(image: nil, style: .ghost, mood: .suspicious, size: 96).figure(phase: phase)
                    .frame(width: 112, height: 120, alignment: .bottom)
            }
        }
        .padding(20)
        .background(Color(white: 0.16))
        save(themed(ghostRun), to: folder.appendingPathComponent("run-cycle-ghost.png"))

        // A custom picture given the same run. The test picture is a blob on a plain
        // background, pushed through the real import pipeline (cut-out, trim, scale).
        if let test = testPicture() {
            let processed = CharacterStore.process(test, removeBackground: true)
            print("custom picture: cutOut=\(processed.cutOut) size=\(processed.image.width)x\(processed.image.height)")
            let picture = NSImage(cgImage: processed.image, size: NSSize(width: processed.image.width, height: processed.image.height))
            let customRun = HStack(spacing: 6) {
                ForEach(phases, id: \.self) { phase in
                    CharacterView(image: picture, mood: .happy, size: 96).figure(phase: phase)
                        .frame(width: 112, height: 124, alignment: .bottom)
                }
            }
            .padding(20)
            .background(Color(white: 0.16))
            save(themed(customRun), to: folder.appendingPathComponent("run-cycle-custom.png"))
        }

        // The floating companion with a speech bubble
        let model = CompanionModel()
        model.mood = .proud
        model.bubble = "Not today! Get back to work."
        model.bubbleOnLeft = true
        model.size = 72
        let companion = CompanionView(model: model)
            .padding(20)
            .background(Color(white: 0.55))
        save(themed(companion), to: folder.appendingPathComponent("companion.png"))

        // The four sizes next to each other, on a mock tab bar, to check the proportions
        let sizes = HStack(alignment: .center, spacing: 28) {
            ForEach(CompanionSize.allCases) { option in
                VStack(spacing: 6) {
                    CharacterView(image: nil, mood: .proud, size: CGFloat(option.points))
                    Text(option.title)
                        .font(Theme.label(10.5))
                        .foregroundColor(Color(white: 0.75))
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.2))
        save(themed(sizes), to: folder.appendingPathComponent("sizes.png"))

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

        settings.customSites = savedSites
        settings.companionMode = savedMode
        settings.characterStyle = savedStyle
        rendering = false
    }

    /// A simple character on a plain backdrop, standing in for a photo the user might pick.
    private static func testPicture() -> CGImage? {
        let side = 512
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // A plain robot: square head, antenna, two legs.
        context.setFillColor(CGColor(red: 0.20, green: 0.45, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 150, y: 140, width: 212, height: 190))
        context.fill(CGRect(x: 246, y: 330, width: 20, height: 60))
        context.fillEllipse(in: CGRect(x: 232, y: 380, width: 48, height: 48))
        context.fill(CGRect(x: 180, y: 80, width: 50, height: 60))
        context.fill(CGRect(x: 282, y: 80, width: 50, height: 60))
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        context.fillEllipse(in: CGRect(x: 190, y: 230, width: 46, height: 46))
        context.fillEllipse(in: CGRect(x: 276, y: 230, width: 46, height: 46))
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.fillEllipse(in: CGRect(x: 208, y: 244, width: 20, height: 20))
        context.fillEllipse(in: CGRect(x: 294, y: 244, width: 20, height: 20))
        return context.makeImage()
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
