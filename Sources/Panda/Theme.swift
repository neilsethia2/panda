import AppKit
import SwiftUI

/// Panda's look follows Apple's own Mac apps: the grouped grey-and-white layout of System
/// Settings, system fonts, the system blue for selection and green switches. Light and dark
/// use Apple's standard system greys.
enum Theme {
    /// Set by the app delegate. Views are rebuilt when it flips.
    static var dark = false

    private static func pick(_ light: Color, _ darkColor: Color) -> Color {
        dark ? darkColor : light
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    /// Window background (grouped background).
    static var surface: Color { pick(rgb(242, 242, 247), rgb(28, 28, 30)) }
    /// Group boxes sitting on the surface.
    static var card: Color { pick(Color.white, rgb(44, 44, 46)) }
    /// Control tracks, chips, quiet fills.
    static var fill: Color { pick(rgb(229, 229, 234), rgb(58, 58, 60)) }
    /// Hairlines and separators.
    static var line: Color { pick(rgb(209, 209, 214), rgb(56, 56, 58)) }
    /// Primary text.
    static var ink: Color { pick(rgb(29, 29, 31), rgb(245, 245, 247)) }
    /// Secondary text.
    static var muted: Color { pick(rgb(110, 110, 115), rgb(152, 152, 157)) }

    /// System blue: selection, prominent buttons.
    static var accent: Color { pick(rgb(0, 122, 255), rgb(10, 132, 255)) }
    /// System green: switches that are on.
    static var green: Color { pick(rgb(52, 199, 89), rgb(48, 209, 88)) }
    static var red: Color { pick(rgb(255, 59, 48), rgb(255, 69, 58)) }
    static var orange: Color { pick(rgb(255, 149, 0), rgb(255, 159, 10)) }
    static var teal: Color { pick(rgb(48, 176, 199), rgb(64, 200, 224)) }
    static var grey: Color { pick(rgb(142, 142, 147), rgb(142, 142, 147)) }

    /// Chart series: Instagram, YouTube, the user's own list.
    static var chart1: Color { accent }
    static var chart2: Color { teal }
    static var chart3: Color { orange }

    /// Sidebar background where the real translucent material cannot be drawn.
    static var sidebarFallback: Color { pick(rgb(232, 232, 237), rgb(36, 36, 38)) }
    /// Raised controls: buttons, the selected segment.
    static var raised: Color { pick(Color.white, rgb(99, 99, 102)) }

    static var surfaceNS: NSColor {
        dark ? NSColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
             : NSColor(red: 242 / 255, green: 242 / 255, blue: 247 / 255, alpha: 1)
    }

    // The character keeps his own colours whatever the theme, because he also walks over
    // other apps' windows.
    static let pandaBlack = Color(white: 0.085)
    static let pandaWhite = Color.white
    static let pandaBelly = Color(white: 0.895)
    static let pandaCheek = Color(white: 0.80)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Big figures, in the rounded face Apple uses for stats.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Captions and small labels.
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

/// The background every screen sits on.
struct SurfaceBackground: View {
    var body: some View {
        Theme.surface
    }
}

/// A group box: white (or raised grey in dark mode) with rounded corners, as in System Settings.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(Theme.dark ? 0 : 0.05), lineWidth: 0.5)
            )
    }
}

/// A switch in the Apple style: green when on, white knob. Drawn in SwiftUI so it looks the
/// same everywhere, including the menu bar panel.
struct PandaToggleStyle: ToggleStyle {
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let width: CGFloat = large ? 44 : 38
        let height: CGFloat = large ? 26 : 22
        let knob: CGFloat = height - 4

        return HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.green : Theme.fill)
                    .frame(width: width, height: height)
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                    .frame(width: knob, height: knob)
                    .padding(.horizontal, 2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// Small rounded label, e.g. "Allowed" or "Connected".
struct Pill: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.body(11, weight: .medium))
            .foregroundColor(filled ? Color.white : Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(filled ? Theme.green : Theme.fill))
    }
}

/// A Mac push button. Prominent ones are filled with the system blue.
struct SoftButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13))
            .foregroundColor(prominent ? Color.white : Theme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.raised)
                    .shadow(color: Color.black.opacity(Theme.dark ? 0.3 : 0.14), radius: 0.8, x: 0, y: 0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(prominent || Theme.dark ? 0 : 0.10), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A segmented control in the Apple style: grey track, raised white segment for the choice.
struct ChoiceChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.0 == selection
                Text(option.1)
                    .font(Theme.body(12.5, weight: selected ? .medium : .regular))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(selected ? Theme.raised : Color.clear)
                            .shadow(color: Color.black.opacity(selected ? 0.16 : 0), radius: 1.2, x: 0, y: 0.8)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.14)) { selection = option.0 }
                    }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7.5, style: .continuous).fill(Theme.fill))
        .fixedSize()
    }
}

/// The frosted sidebar material from macOS itself.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
