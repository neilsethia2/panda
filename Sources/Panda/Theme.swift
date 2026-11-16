import AppKit
import SwiftUI

/// Panda's look: black, white and grey, matte, with a fine grain over the background.
/// No accent colour. Light and dark share the same structure with the greys inverted.
enum Theme {
    /// Set by `ThemeController`. Views are rebuilt when it flips.
    static var dark = false

    private static func grey(_ light: Double, _ darkValue: Double) -> Color {
        Color(white: dark ? darkValue : light)
    }

    /// Window and panel background.
    static var surface: Color { grey(0.918, 0.075) }
    /// Cards sitting on the surface.
    static var card: Color { grey(0.962, 0.112) }
    /// Chips, secondary buttons, switch tracks.
    static var fill: Color { grey(0.868, 0.178) }
    /// Hairlines.
    static var line: Color { grey(0.820, 0.215) }
    /// Text and anything "on".
    static var ink: Color { grey(0.070, 0.945) }
    static var muted: Color { grey(0.435, 0.560) }
    /// Second and third series in charts.
    static var series2: Color { grey(0.560, 0.470) }
    static var series3: Color { grey(0.760, 0.270) }

    static var surfaceNS: NSColor { NSColor(white: dark ? 0.075 : 0.918, alpha: 1) }

    // The panda keeps his own colours whatever the theme, because he also walks over
    // other apps' windows.
    static let pandaBlack = Color(white: 0.085)
    static let pandaWhite = Color.white
    static let pandaBelly = Color(white: 0.895)
    static let pandaCheek = Color(white: 0.80)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Big figures: light weight, fixed-width digits so they do not jiggle when they change.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default).monospacedDigit()
    }

    /// Small technical labels: section headings, legends.
    static func label(_ size: CGFloat = 10.5) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// A fine film-grain texture, generated once and tiled. It is what makes the flat greys
/// read as a matte material and not as a blank rectangle.
enum Grain {
    static let image: NSImage = {
        let side = 192
        var state: UInt64 = 0x9E3779B97F4A7C15
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            // xorshift: the same pattern on every launch
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let value = UInt8(truncatingIfNeeded: state >> 24)
            let alpha = UInt8(truncatingIfNeeded: (state >> 40) % 56)
            // premultiplied
            let premultiplied = UInt8((UInt16(value) * UInt16(alpha)) / 255)
            pixels[i * 4] = premultiplied
            pixels[i * 4 + 1] = premultiplied
            pixels[i * 4 + 2] = premultiplied
            pixels[i * 4 + 3] = alpha
        }
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            return NSImage(size: NSSize(width: 96, height: 96))
        }
        // 192 pixels shown at 96 points: one grain per physical pixel on a Retina screen.
        return NSImage(cgImage: cg, size: NSSize(width: 96, height: 96))
    }()
}

struct GrainOverlay: View {
    var strength: Double = 1

    var body: some View {
        Image(nsImage: Grain.image)
            .resizable(resizingMode: .tile)
            .opacity((Theme.dark ? 0.34 : 0.26) * strength)
            .blendMode(Theme.dark ? .screen : .multiply)
            .allowsHitTesting(false)
    }
}

/// The background every screen sits on.
struct SurfaceBackground: View {
    var body: some View {
        ZStack {
            Theme.surface
            GrainOverlay()
        }
    }
}

/// A flat card: slightly lifted grey, hairline edge, no drop shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

/// A switch drawn entirely in SwiftUI: ink when on, grey when off.
struct PandaToggleStyle: ToggleStyle {
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let width: CGFloat = large ? 50 : 40
        let height: CGFloat = large ? 28 : 23
        let knob: CGFloat = height - 6

        return HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.ink : Theme.fill)
                    .overlay(Capsule().stroke(configuration.isOn ? Color.clear : Theme.line, lineWidth: 1))
                    .frame(width: width, height: height)
                Circle()
                    .fill(configuration.isOn ? Theme.card : Theme.muted)
                    .frame(width: knob, height: knob)
                    .padding(.horizontal, 3)
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// Small label, e.g. "Allowed" or "Connected".
struct Pill: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.body(11, weight: .medium))
            .foregroundColor(filled ? Theme.surface : Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(filled ? Theme.ink : Theme.fill))
    }
}

struct SoftButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5, weight: .medium))
            .foregroundColor(prominent ? Theme.surface : Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(prominent ? Theme.ink : Theme.fill)
            )
            .overlay(Capsule().stroke(prominent ? Color.clear : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A row of mutually exclusive chips. Used instead of the system segmented control so it
/// matches the rest of the interface.
struct ChoiceChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.0 == selection
                Text(option.1)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundColor(selected ? Theme.surface : Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6.5)
                    .background(Capsule().fill(selected ? Theme.ink : Theme.fill))
                    .overlay(Capsule().stroke(selected ? Color.clear : Theme.line, lineWidth: 1))
                    .contentShape(Capsule())
                    .onTapGesture { selection = option.0 }
            }
        }
    }
}
