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
    /// Height of the character in points.
    @Published var size: CGFloat = 72
    /// The user's own picture, or nil for the panda.
    @Published var image: NSImage?
    @Published var flipImage = true
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

    /// The window is a fixed transparent canvas. The character stands bottom-centre and the
    /// speech bubble appears to one side of him.
    static let panelSize = CGSize(width: 372, height: 150)

    var body: some View {
        let size = model.size
        let bubbleOffset = size / 2 + 66

        return ZStack(alignment: .bottom) {
            if let text = model.bubble {
                SpeechBubble(text: text, tailOnRight: model.bubbleOnLeft)
                    .offset(x: model.bubbleOnLeft ? -bubbleOffset : bubbleOffset, y: -max(6, size * 0.32))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            CharacterView(
                image: model.image,
                mood: model.mood,
                size: size,
                blink: model.blink,
                walking: model.walking,
                facingLeft: model.facingLeft,
                flipImage: model.flipImage
            )
            .scaleEffect(model.breathe ? 1.035 : 1.0, anchor: .bottom)
            .animation(.easeInOut(duration: 0.9), value: model.breathe)
            .padding(.bottom, CompanionView.footPadding)
        }
        .frame(width: CompanionView.panelSize.width, height: CompanionView.panelSize.height, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: model.bubble)
    }

    /// Gap between the bottom of the window and the character's feet.
    static let footPadding: CGFloat = 4
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

/// The floating character: a small borderless window that runs to the offending tab when
/// something gets blocked, closes it, and leaves the way he came. Depending on the setting
/// he either rests in a corner between catches or is not on screen at all.
final class CompanionController {
    let model = CompanionModel()
    var onPoke: (() -> Void)?

    private let settings: AppSettings
    private let characters: CharacterStore
    private let panel: NSPanel
    private var idleTimer: Timer?
    private var sequence = 0
    private var busy = false
    private var pending: DispatchWorkItem?
    private var imageWatch: AnyCancellable?

    /// How he came in on the current run, so he can leave the same way.
    private var entryUsed: EntrySide = .home
    private var runScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private var panelSize: NSSize { NSSize(width: CompanionView.panelSize.width, height: CompanionView.panelSize.height) }
    private var characterSize: CGFloat { model.size }
    /// Transparent space on each side of the character inside the window.
    private var sideInset: CGFloat { (panelSize.width - characterSize) / 2 }

    init(settings: AppSettings, characters: CharacterStore = .shared) {
        self.settings = settings
        self.characters = characters

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

        applyLook()
        panel.setFrameOrigin(homeOrigin())
        refresh()

        // A new picture was chosen or removed.
        imageWatch = characters.$image.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Size and picture, from the settings.
    private func applyLook() {
        let size = CGFloat(settings.companionSize.points)
        if model.size != size { model.size = size }
        let image = settings.characterStyle == .custom ? characters.image : nil
        if model.image !== image { model.image = image }
        if model.flipImage != settings.flipWhenWalkingLeft { model.flipImage = settings.flipWhenWalkingLeft }
    }

    private func screenFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Window origin that puts the character just outside one edge of `frame`.
    private func offscreenOrigin(_ side: EntrySide, frame: NSRect, level: NSPoint) -> NSPoint {
        switch side {
        case .left:
            return NSPoint(x: frame.minX - sideInset - characterSize - 6, y: level.y)
        case .right:
            return NSPoint(x: frame.maxX + 6 - sideInset, y: level.y)
        case .top:
            return NSPoint(x: level.x, y: frame.maxY + 6)
        case .nearest, .home:
            return level
        }
    }

    // MARK: Home position

    private func defaultHome() -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // The character is centred in the window, so the transparent part hangs off-screen.
        let centreX = visible.maxX - characterSize / 2 - 26
        return NSPoint(x: centreX - panelSize.width / 2, y: visible.minY + 8)
    }

    private func homeOrigin() -> NSPoint {
        let d = UserDefaults.standard
        guard d.object(forKey: "companionX") != nil, d.object(forKey: "companionY") != nil else {
            return defaultHome()
        }
        let origin = NSPoint(x: d.double(forKey: "companionX"), y: d.double(forKey: "companionY"))
        let centre = NSPoint(x: origin.x + panelSize.width / 2, y: origin.y + characterSize / 2)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(centre) }
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
        if !busy, panel.isVisible { panel.setFrameOrigin(defaultHome()) }
    }

    // MARK: Resting state

    private var restingMood: PandaMood { settings.protectionActive ? .happy : .sleeping }

    /// Bring the character in line with the current settings. Called on every settings change.
    func refresh() {
        guard !busy else { return }
        applyLook()
        model.mood = restingMood
        model.walking = false
        switch settings.companionMode {
        case .always:
            let home = homeOrigin()
            let away = abs(panel.frame.origin.x - home.x) > 1 || abs(panel.frame.origin.y - home.y) > 1
            if !panel.isVisible || away {
                // Back in his corner with a quick fade, not a slide across the screen.
                panel.alphaValue = 0
                panel.setFrameOrigin(home)
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    panel.animator().alphaValue = 1
                }
            }
            startIdleTimer()
        case .onCatch, .menuBarOnly:
            panel.orderOut(nil)
            panel.alphaValue = 1
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

    /// Run to `anchor` (a point on the tab, in screen coordinates) and arrive after `travel`
    /// seconds. With no anchor he reacts where he stands.
    func pounce(to anchor: NSPoint?, travel: TimeInterval, kind: BlockKind) {
        guard settings.companionMode != .menuBarOnly else { return }
        pending?.cancel()
        sequence += 1
        let ticket = sequence
        busy = true
        applyLook()

        let home = homeOrigin()
        let resting = settings.companionMode == .always
        var entry = settings.entrySide
        var target: NSPoint
        let start: NSPoint

        if let anchor = anchor, settings.walkToTab {
            let frame = screenFrame(containing: anchor)
            runScreen = frame
            // Feet land in the tab strip, body pokes up above it.
            target = NSPoint(x: anchor.x - panelSize.width / 2, y: anchor.y - 20 - CompanionView.footPadding)
            // Keep his head on the screen when the browser window is flush with the top.
            target.y = min(target.y, frame.maxY - characterSize - CompanionView.footPadding - 2)
            target.y = max(target.y, frame.minY)

            if entry == .home && !resting { entry = .nearest }
            if entry == .nearest {
                entry = (anchor.x - frame.minX) < (frame.maxX - anchor.x) ? .left : .right
            }
            switch entry {
            case .home:
                start = panel.isVisible ? panel.frame.origin : home
            default:
                start = offscreenOrigin(entry, frame: frame, level: target)
            }
        } else {
            // No tab position, or running is switched off: react on the spot.
            entry = .home
            target = (resting && panel.isVisible) ? panel.frame.origin : home
            start = target
            runScreen = screenFrame(containing: NSPoint(x: target.x + panelSize.width / 2, y: target.y))
        }
        entryUsed = entry

        model.bubble = nil
        model.mood = kind == .shorts ? .shocked : .suspicious
        model.facingLeft = target.x < start.x - 1

        panel.alphaValue = 1
        panel.setFrameOrigin(start)
        if !panel.isVisible { panel.orderFrontRegardless() }

        let distance = hypot(target.x - start.x, target.y - start.y)
        if distance < 2 {
            model.walking = false
            after(max(travel, 0.05), ticket: ticket) { [weak self] in self?.arrived(ticket: ticket) }
            return
        }

        model.walking = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = max(travel, 0.25)
            // Fast off the mark, settling as he reaches the tab.
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(origin: target, size: panelSize), display: true)
        }, completionHandler: { [weak self] in
            self?.arrived(ticket: ticket)
        })
    }

    private func arrived(ticket: Int) {
        guard ticket == sequence else { return }
        model.walking = false
        model.facingLeft = false
        model.mood = .proud
        // With the message switched off there is nothing to read, so he leaves sooner.
        let linger = settings.showBubble ? 2.3 : 0.8
        after(linger, ticket: ticket) { [weak self] in self?.leave(ticket: ticket) }
    }

    /// Show a line of text next to the character. Picks the side with more room.
    func say(_ text: String) {
        guard panel.isVisible else { return }
        let centre = NSPoint(x: panel.frame.midX, y: panel.frame.minY + characterSize / 2)
        let frame = screenFrame(containing: centre)
        model.bubbleOnLeft = centre.x > frame.midX
        model.bubble = text
    }

    /// Called when a tab was actually closed.
    func confirmCatch(message: String) {
        guard settings.companionMode != .menuBarOnly, settings.showBubble else { return }
        say(message)
    }

    private func leave(ticket: Int) {
        guard ticket == sequence else { return }
        model.bubble = nil
        model.mood = restingMood

        let current = panel.frame.origin
        var side = entryUsed
        if side == .home && settings.companionMode != .always {
            let centreX = panel.frame.midX
            side = (centreX - runScreen.minX) < (runScreen.maxX - centreX) ? .left : .right
        }
        let destination = side == .home ? homeOrigin() : offscreenOrigin(side, frame: runScreen, level: current)

        let distance = hypot(destination.x - current.x, destination.y - current.y)
        if distance < 2 {
            finish(ticket: ticket)
            return
        }

        model.facingLeft = destination.x < current.x - 1
        model.walking = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = min(0.8, max(0.3, Double(distance) / 1800))
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
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
        if entryUsed != .home || settings.companionMode != .always {
            panel.orderOut(nil)
        }
        refresh()
    }

    // MARK: Celebrating

    func celebrate(message: String) {
        guard settings.companionMode == .always, !busy, panel.isVisible else { return }
        sequence += 1
        let ticket = sequence
        busy = true
        entryUsed = .home
        model.mood = .celebrating
        model.walking = true
        if settings.showBubble { say(message) }
        after(1.2, ticket: ticket) { [weak self] in self?.model.walking = false }
        after(4.0, ticket: ticket) { [weak self] in
            guard let self = self else { return }
            self.model.bubble = nil
            self.finish(ticket: ticket)
        }
    }

    /// A quick word when you click him.
    func chat(_ text: String) {
        guard !busy, panel.isVisible else { return }
        sequence += 1
        let ticket = sequence
        say(text)
        after(3.0, ticket: ticket) { [weak self] in self?.model.bubble = nil }
    }

    /// Play one run across the top of the screen so the user can see their settings in action.
    func demo() {
        guard settings.companionMode != .menuBarOnly else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = NSPoint(x: frame.midX, y: frame.maxY - 120)
        pounce(to: anchor, travel: AppSettings.walkDuration, kind: .instagram)
        if settings.showBubble {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.walkDuration + 0.05) { [weak self] in
                self?.say("This is how I close a tab.")
            }
        }
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
