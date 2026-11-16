import AppKit
import SwiftUI

/// Things the interface can ask the app to do.
final class AppActions: ObservableObject {
    var openDashboard: () -> Void = {}
    var openSettings: () -> Void = {}
    var openSetup: () -> Void = {}
    var closePopover: () -> Void = {}
    var openBlocklist: () -> Void = {}
    var resetCompanion: () -> Void = {}
    var demoCompanion: () -> Void = {}
    var retryBrowserAccess: () -> Void = {}
    var quit: () -> Void = {}
}

/// The panda in the menu bar and the little panel that opens from it.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let settings: AppSettings

    static let popoverSize = NSSize(width: 320, height: 548)

    init(settings: AppSettings, stats: StatsStore, actions: AppActions) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let root = PopoverView()
            .environmentObject(settings)
            .environmentObject(stats)
            .environmentObject(actions)
        let host = NSHostingController(rootView: root)
        host.view.frame = NSRect(origin: .zero, size: StatusItemController.popoverSize)

        popover.contentViewController = host
        popover.contentSize = StatusItemController.popoverSize
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Panda"
            button.setAccessibilityLabel("Panda")
        }
        refreshIcon()
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Match the popover chrome to the current light or dark theme.
    func applyTheme() {
        popover.appearance = NSAppearance(named: Theme.dark ? .darkAqua : .aqua)
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let awake = settings.protectionActive
        button.image = StatusItemController.icon(awake: awake)
        button.appearsDisabled = !awake
        button.toolTip = awake ? "Panda: protection on" : "Panda: protection off"
    }

    /// A panda face drawn as a template image, so macOS tints it for light and dark menu bars.
    static func icon(awake: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Ears
            NSBezierPath(ovalIn: NSRect(x: 1.2, y: 1.4, width: 5.6, height: 5.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.2, y: 1.4, width: 5.6, height: 5.6)).fill()

            // Head: clear the inside so the ears tuck behind it, then outline it.
            let headRect = NSRect(x: 2.1, y: 3.4, width: 13.8, height: 12.6)
            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                context.compositingOperation = .clear
                NSBezierPath(ovalIn: headRect).fill()
                context.restoreGraphicsState()
            }
            let head = NSBezierPath(ovalIn: headRect.insetBy(dx: 0.6, dy: 0.6))
            head.lineWidth = 1.2
            head.stroke()

            if awake {
                // Eye patches
                let left = NSBezierPath(ovalIn: NSRect(x: -1.7, y: -2.2, width: 3.4, height: 4.4))
                var leftTransform = AffineTransform(translationByX: 6.2, byY: 9.4)
                leftTransform.rotate(byRadians: 0.4)
                left.transform(using: leftTransform)
                left.fill()

                let right = NSBezierPath(ovalIn: NSRect(x: -1.7, y: -2.2, width: 3.4, height: 4.4))
                var rightTransform = AffineTransform(translationByX: 11.8, byY: 9.4)
                rightTransform.rotate(byRadians: -0.4)
                right.transform(using: rightTransform)
                right.fill()
            } else {
                // Closed, sleepy eyes
                for x in [4.6, 10.2] {
                    let eye = NSBezierPath()
                    eye.move(to: NSPoint(x: x, y: 9.2))
                    eye.curve(to: NSPoint(x: x + 3.2, y: 9.2),
                              controlPoint1: NSPoint(x: x + 0.8, y: 10.8),
                              controlPoint2: NSPoint(x: x + 2.4, y: 10.8))
                    eye.lineWidth = 1.2
                    eye.lineCapStyle = .round
                    eye.stroke()
                }
            }

            // Nose
            NSBezierPath(ovalIn: NSRect(x: 8.0, y: 11.6, width: 2.0, height: 1.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
