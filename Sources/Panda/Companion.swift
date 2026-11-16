import AppKit
import Combine
import QuartzCore
import SwiftUI

final class CompanionModel: ObservableObject {
    @Published var mood: PandaMood = .happy
    @Published var blink = false
    @Published var breathe = false
    @Published var walking = false
    @Published var facingLeft = false
    @Published var bubble: String?
    @Published var bubbleOnLeft = true
}

struct SpeechBubble: View {
    let text: String
    /// True when the bubble sits to the left of the panda, so its tail points right.
    let tailOnRight: Bool

    var body: some View {
        Text(text)
            .font(Theme.body(11.5, weight: .semibold))
            .foregroundColor(Theme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 112)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.16), radius: 5, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Theme.ink, lineWidth: 1.6)
            )
            .overlay(
                BubbleTail()
                    .fill(Color.white)
                    .overlay(BubbleTail().stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
                    .frame(width: 9, height: 12)
                    .scaleEffect(x: tailOnRight ? 1 : -1, y: 1)
                    .offset(x: tailOnRight ? 7.5 : -7.5),
                alignment: tailOnRight ? .trailing : .leading
            )
    }
}

/// A small open triangle pointing right. The left edge is left open so it merges with the bubble.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

struct CompanionView: View {
    @ObservedObject var model: CompanionModel

    static let panelSize = CGSize(width: 340, height: 112)
    static let pandaSize: CGFloat = 92

    var body: some View {
        ZStack {
            if let text = model.bubble {
                SpeechBubble(text: text, tailOnRight: model.bubbleOnLeft)
                    .offset(x: model.bubbleOnLeft ? -108 : 108, y: -8)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            PandaView(
                mood: model.mood,
                size: CompanionView.pandaSize,
                blink: model.blink,
                walking: model.walking,
                facingLeft: model.facingLeft
            )
            .scaleEffect(model.breathe ? 1.035 : 1.0, anchor: .bottom)
            .animation(.easeInOut(duration: 0.9), value: model.breathe)
        }
        .frame(width: CompanionView.panelSize.width, height: CompanionView.panelSize.height, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: model.bubble)
    }
}

/// Sits on top of the SwiftUI view and turns mouse input into "drag the panda" or "poke the panda".
/// Transparent pixels of the window let clicks fall through to whatever is underneath.
final class CompanionMouseView: NSView {
    var onClick: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var downMouse = NSPoint.zero
    private var downOrigin = NSPoint.zero
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downMouse = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - downMouse.x
        let dy = now.y - downMouse.y
        if abs(dx) > 3 || abs(dy) > 3 { dragged = true }
        if dragged {
            window?.setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { onDragEnd?() } else { onClick?() }
    }
}

/// The floating desktop panda: a small borderless window that rests in a corner,
/// runs to the offending tab when something gets blocked, and walks home again.
final class CompanionController {
    let model = CompanionModel()
    var onPoke: (() -> Void)?

    private let settings: AppSettings
    private let panel: NSPanel
    private var idleTimer: Timer?
    private var sequence = 0
    private var busy = false
    private var pending: DispatchWorkItem?

    private var panelSize: NSSize { NSSize(width: CompanionView.panelSize.width, height: CompanionView.panelSize.height) }

    init(settings: AppSettings) {
        self.settings = settings

        let size = NSSize(width: CompanionView.panelSize.width, height: CompanionView.panelSize.height)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        let host = NSHostingView(rootView: CompanionView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]

        let mouse = CompanionMouseView(frame: NSRect(origin: .zero, size: size))
        mouse.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(host)
        container.addSubview(mouse)
        panel.contentView = container

        mouse.onClick = { [weak self] in self?.onPoke?() }
        mouse.onDragEnd = { [weak self] in self?.saveHome() }

        panel.setFrameOrigin(homeOrigin())
        refresh()
    }

    // MARK: Home position

    private func defaultHome() -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The panda is centred in the panel, so let the transparent part hang off-screen.
        let pandaCentreX = visible.maxX - 70
        return NSPoint(x: pandaCentreX - panelSize.width / 2, y: visible.minY + 10)
    }

    private func homeOrigin() -> NSPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: "companionX") != nil, d.object(forKey: "companionY") != nil else {
            return defaultHome()
        }
        let origin = NSPoint(x: d.double(forKey: "companionX"), y: d.double(forKey: "companionY"))
        let pandaCentre = NSPoint(x: origin.x + panelSize.width / 2, y: origin.y + 46)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(pandaCentre) }
        return onScreen ? origin : defaultHome()
    }

    private func saveHome() {
        guard !busy else { return }
        UserDefaults.standard.set(Double(panel.frame.origin.x), forKey: "companionX")
        UserDefaults.standard.set(Double(panel.frame.origin.y), forKey: "companionY")
    }

    func resetHome() {
        UserDefaults.standard.removeObject(forKey: "companionX")
        UserDefaults.standard.removeObject(forKey: "companionY")
        if !busy { panel.setFrameOrigin(defaultHome()) }
    }

    // MARK: Resting state

    private var restingMood: PandaMood { settings.protectionActive ? .happy : .sleeping }

    /// Bring the panda in line with the current settings. Called on every settings change.
    func refresh() {
        guard !busy else { return }
        model.mood = restingMood
        model.walking = false
        switch settings.companionMode {
        case .always:
            if !panel.isVisible {
                panel.setFrameOrigin(homeOrigin())
                panel.orderFrontRegardless()
            }
            startIdleTimer()
        case .onCatch, .menuBarOnly:
            panel.orderOut(nil)
            stopIdleTimer()
        }
    }

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        // One sleepy timer instead of a looping animation: a blink and a breath every few seconds.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.idleTick()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func idleTick() {
        guard !busy, panel.isVisible, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        model.breathe = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.model.breathe = false
        }
        if model.mood == .happy {
            model.blink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                self?.model.blink = false
            }
        }
    }

    // MARK: Catching

    /// Run to `anchor` (a point on the tab, in screen coordinates) and arrive after `travel` seconds.
    /// With no anchor the panda reacts where he stands.
    func pounce(to anchor: NSPoint?, travel: TimeInterval, kind: BlockKind) {
        guard settings.companionMode != .menuBarOnly else { return }
        pending?.cancel()
        sequence += 1
        let ticket = sequence
        busy = true

        let home = homeOrigin()
        var target = panel.isVisible ? panel.frame.origin : home
        var start = target

        if let anchor = anchor, settings.walkToTab {
            // Feet land in the tab strip, body pokes up above it.
            target = NSPoint(x: anchor.x - panelSize.width / 2, y: anchor.y - 20)
            // Keep his head on the screen when the browser window is flush with the top.
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
                target.y = min(target.y, screen.frame.maxY - panelSize.height)
                target.y = max(target.y, screen.frame.minY)
            }
            if panel.isVisible {
                start = panel.frame.origin
            } else {
                // Not on screen: come in from the nearest side, like in the video.
                let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
                let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let fromLeft = (anchor.x - frame.minX) < (frame.maxX - anchor.x)
                let pandaInset = (panelSize.width - CompanionView.pandaSize) / 2
                start = NSPoint(
                    x: fromLeft ? frame.minX - panelSize.width + pandaInset : frame.maxX - pandaInset,
                    y: target.y
                )
            }
        } else if !panel.isVisible {
            target = home
            start = home
        }

        model.bubble = nil
        model.mood = kind == .instagram ? .suspicious : .shocked
        model.facingLeft = target.x < start.x - 1

        if !panel.isVisible {
            panel.setFrameOrigin(start)
            panel.orderFrontRegardless()
        }

        let distance = hypot(target.x - start.x, target.y - start.y)
        if distance < 2 {
            model.walking = false
            after(max(travel, 0.05), ticket: ticket) { [weak self] in self?.arrived(kind: kind, ticket: ticket) }
            return
        }

        model.walking = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = max(travel, 0.25)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: target, size: panelSize), display: true)
        }, completionHandler: { [weak self] in
            self?.arrived(kind: kind, ticket: ticket)
        })
    }

    private func arrived(kind: BlockKind, ticket: Int) {
        guard ticket == sequence else { return }
        model.walking = false
        model.facingLeft = false
        model.mood = .proud
        after(2.6, ticket: ticket) { [weak self] in self?.goHome(ticket: ticket) }
    }

    /// Show a line of text next to the panda. Picks the side with more room.
    func say(_ text: String) {
        guard panel.isVisible else { return }
        let centreX = panel.frame.midX
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: centreX, y: panel.frame.midY)) } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.bubbleOnLeft = centreX > frame.midX
        model.bubble = text
    }

    /// Called when a tab was actually closed.
    func confirmCatch(message: String) {
        guard settings.companionMode != .menuBarOnly else { return }
        say(message)
    }

    private func goHome(ticket: Int) {
        guard ticket == sequence else { return }
        model.bubble = nil
        model.mood = restingMood

        let current = panel.frame.origin
        var destination = homeOrigin()
        if settings.companionMode == .onCatch {
            // Walk off the nearest side of the screen.
            let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
            let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let toLeft = (centre.x - frame.minX) < (frame.maxX - centre.x)
            let pandaInset = (panelSize.width - CompanionView.pandaSize) / 2
            destination = NSPoint(
                x: toLeft ? frame.minX - panelSize.width + pandaInset : frame.maxX - pandaInset,
                y: current.y
            )
        }

        let distance = hypot(destination.x - current.x, destination.y - current.y)
        if distance < 2 {
            finish(ticket: ticket)
            return
        }

        model.facingLeft = destination.x < current.x
        model.walking = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = min(1.1, max(0.45, Double(distance) / 1400))
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: destination, size: panelSize), display: true)
        }, completionHandler: { [weak self] in
            self?.finish(ticket: ticket)
        })
    }

    private func finish(ticket: Int) {
        guard ticket == sequence else { return }
        busy = false
        model.walking = false
        model.facingLeft = false
        refresh()
    }

    // MARK: Celebrating

    func celebrate(message: String) {
        guard settings.companionMode == .always, !busy, panel.isVisible else { return }
        sequence += 1
        let ticket = sequence
        busy = true
        model.mood = .celebrating
        model.walking = true
        say(message)
        after(1.2, ticket: ticket) { [weak self] in self?.model.walking = false }
        after(4.0, ticket: ticket) { [weak self] in
            guard let self = self else { return }
            self.model.bubble = nil
            self.finish(ticket: ticket)
        }
    }

    /// A quick word from the panda when you click him.
    func chat(_ text: String) {
        guard !busy, panel.isVisible else { return }
        sequence += 1
        let ticket = sequence
        say(text)
        after(3.0, ticket: ticket) { [weak self] in self?.model.bubble = nil }
    }

    private func after(_ delay: TimeInterval, ticket: Int, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, ticket == self.sequence else { return }
            work()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
