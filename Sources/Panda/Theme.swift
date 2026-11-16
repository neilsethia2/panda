import SwiftUI

/// Panda's look: soft cream, black and white, one quiet bamboo green for "on".
enum Theme {
    static let cream = Color(red: 0.984, green: 0.965, blue: 0.925)
    static let creamDeep = Color(red: 0.953, green: 0.906, blue: 0.812)
    static let creamLine = Color(red: 0.91, green: 0.87, blue: 0.79)
    static let card = Color.white
    static let ink = Color(red: 0.122, green: 0.114, blue: 0.102)
    static let muted = Color(red: 0.50, green: 0.475, blue: 0.43)
    static let bamboo = Color(red: 0.40, green: 0.60, blue: 0.44)
    static let blush = Color(red: 0.97, green: 0.80, blue: 0.74)
    static let gold = Color(red: 0.91, green: 0.76, blue: 0.42)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A white rounded card with a soft shadow.
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}

/// A pill switch drawn entirely in SwiftUI: black when on, cream when off.
struct PandaToggleStyle: ToggleStyle {
    var large: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let width: CGFloat = large ? 54 : 42
        let height: CGFloat = large ? 31 : 25
        let knob: CGFloat = height - 6

        return HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.ink : Theme.creamLine)
                    .frame(width: width, height: height)
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .frame(width: knob, height: knob)
                    .padding(.horizontal, 3)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

/// Small rounded label, e.g. "Allowed" or "ON".
struct Pill: View {
    let text: String
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.body(11, weight: .semibold))
            .foregroundColor(filled ? Theme.cream : Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(Capsule().fill(filled ? Theme.ink : Theme.creamDeep))
    }
}

struct SoftButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5, weight: .semibold))
            .foregroundColor(prominent ? Theme.cream : Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(prominent ? Theme.ink : Theme.creamDeep)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
