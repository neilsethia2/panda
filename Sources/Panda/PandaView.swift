import AppKit
import SwiftUI

enum PandaMood: String, CaseIterable, Equatable {
    case happy        // protection on, all good
    case suspicious   // spotted something on the blocklist
    case shocked      // spotted a Short
    case proud        // just closed something
    case celebrating  // you stayed focused
    case sleeping     // protection off
}

/// The panda used around the app's own screens.
struct PandaView: View {
    var mood: PandaMood
    var size: CGFloat = 96
    var blink: Bool = false
    var walking: Bool = false
    var facingLeft: Bool = false

    var body: some View {
        CharacterView(image: nil, mood: mood, size: size, blink: blink, walking: walking, facingLeft: facingLeft)
    }
}

/// The character that runs across the screen: the panda, or any picture the user chose.
/// While `walking` is true it plays a real run cycle (legs, arms, bob and lean for the panda;
/// hop, rock and squash for a custom picture). The cycle is driven by the display's refresh
/// only for as long as he is moving, so it costs nothing at rest.
struct CharacterView: View {
    var image: NSImage?
    var mood: PandaMood
    var size: CGFloat = 96
    var blink: Bool = false
    var walking: Bool = false
    var facingLeft: Bool = false
    var flipImage: Bool = true

    /// Full left-right step cycles per second. Quick, so it reads as a scurry.
    static let cyclesPerSecond: Double = 4.4

    @State private var pop = false

    var body: some View {
        Group {
            if walking {
                TimelineView(.animation) { context in
                    figure(phase: context.date.timeIntervalSinceReferenceDate * 2 * Double.pi * CharacterView.cyclesPerSecond)
                }
            } else {
                figure(phase: nil)
            }
        }
        .scaleEffect(pop ? 1.08 : 1, anchor: .bottom)
        .onChange(of: mood) { _ in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
            }
        }
        .accessibilityLabel(Text(image == nil ? "Panda, \(mood.rawValue)" : "Your character"))
    }

    /// One frame. `phase` is the position in the run cycle in radians, or nil when standing.
    func figure(phase: Double?) -> some View {
        let moving = phase != nil
        let angle: Double = phase ?? 0
        let swing: Double = moving ? sin(angle) : 0
        let lift: Double = abs(swing)
        let direction: Double = facingLeft ? -1 : 1
        let custom = image != nil

        // The panda bobs inside his own drawing; a picture needs the whole image to hop.
        let hop: CGFloat = size * CGFloat((custom ? 0.11 : 0.035) * lift)
        let lean: Double = moving ? direction * (custom ? 5 : 7) : 0
        let rock: Double = swing * (custom ? 9 : 3.5)
        let squash: CGFloat = (custom && moving) ? CGFloat(0.06 * cos(angle * 2)) : 0
        let mirrored = facingLeft && (!custom || flipImage)

        return Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size, alignment: .bottom)
                    .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
            } else {
                PandaCanvas(mood: mood, blink: blink, stride: phase)
                    .frame(width: size, height: size)
            }
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .rotationEffect(.degrees(lean + rock), anchor: .bottom)
        .offset(y: -hop)
    }
}

/// The panda, drawn in one Canvas pass in a 100 x 100 space so he is cheap to render and
/// stays sharp at any size. Always black and white, whatever the app's theme.
struct PandaCanvas: View {
    var mood: PandaMood
    var blink: Bool = false
    /// Position in the run cycle in radians. Nil draws him standing still.
    var stride: Double? = nil

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100
            ctx.scaleBy(x: scale, y: scale)

            let ink = GraphicsContext.Shading.color(Theme.pandaBlack)
            let white = GraphicsContext.Shading.color(Theme.pandaWhite)
            let belly = GraphicsContext.Shading.color(Theme.pandaBelly)
            let outline: CGFloat = 2.2

            // Run cycle. `s` swings between -1 and 1 once per pair of steps.
            let running = stride != nil
            let s = CGFloat(stride.map { sin($0) } ?? 0)
            let c = CGFloat(stride.map { cos($0) } ?? 0)
            let bob = running ? -2.4 * abs(s) : 0                 // body rises on every step
            let headBob = running ? bob - 1.4 * abs(CGFloat(sin((stride ?? 0) - 0.7))) : 0
            let glance: CGFloat = running ? 1.7 : 0               // eyes look where he is going

            // Ground shadow (shrinks a touch while he is in the air)
            let shadowWidth: CGFloat = running ? 44 - 6 * abs(s) : 50
            ctx.fill(PandaCanvas.ellipse(50, 95.5, shadowWidth, 6), with: .color(Color.black.opacity(0.13)))

            // Feet: one swings forward and lifts while the other pushes back.
            let leftLift = running ? 5.5 * max(0, s) : 0
            let rightLift = running ? 5.5 * max(0, -s) : 0
            let leftFoot = PandaCanvas.ellipse(35 + 6 * c, 90 - leftLift, 21, 13)
            let rightFoot = PandaCanvas.ellipse(65 - 6 * c, 90 - rightLift, 21, 13)

            let body = PandaCanvas.ellipse(50, 76 + bob, 52, 38)

            // Arms: pump opposite to the feet while running.
            let armsUp = mood == .celebrating
            let rightUp = mood == .celebrating || mood == .proud
            let leftArm = armsUp
                ? PandaCanvas.capsule(cx: 21, cy: 58 + bob, w: 12, h: 25, angle: -0.75)
                : PandaCanvas.capsule(cx: 27 - 3.5 * s, cy: 75 + bob, w: 12, h: 24, angle: 0.32 + 0.55 * s)
            let rightArm = rightUp
                ? PandaCanvas.capsule(cx: 79, cy: 58 + bob, w: 12, h: 25, angle: 0.75)
                : PandaCanvas.capsule(cx: 73 - 3.5 * s, cy: 75 + bob, w: 12, h: 24, angle: -0.32 + 0.55 * s)

            // Everything from here up rides on the head.
            let hy = headBob
            let hx: CGFloat = running ? 1.2 * c : 0
            let leftEar = PandaCanvas.ellipse(25 + hx, 19 + hy, 25, 25)
            let rightEar = PandaCanvas.ellipse(75 + hx, 19 + hy, 25, 25)
            let head = PandaCanvas.ellipse(50 + hx, 43 + hy, 78, 66)

            // A white edge behind the whole figure, like a sticker, so his black ears and
            // limbs do not vanish over a dark tab bar or a dark theme.
            for part in [leftFoot, rightFoot, leftArm, rightArm, leftEar, rightEar, body, head] {
                ctx.stroke(part, with: white, lineWidth: 5)
            }

            ctx.fill(leftFoot, with: ink)
            ctx.fill(rightFoot, with: ink)

            ctx.fill(body, with: white)
            ctx.stroke(body, with: ink, lineWidth: outline)
            ctx.fill(PandaCanvas.ellipse(50, 80 + bob, 26, 20), with: belly)

            ctx.fill(leftArm, with: ink)
            ctx.fill(rightArm, with: ink)

            ctx.fill(leftEar, with: ink)
            ctx.fill(rightEar, with: ink)

            ctx.fill(head, with: white)
            ctx.stroke(head, with: ink, lineWidth: outline)

            // Eye patches
            ctx.fill(PandaCanvas.tiltedEllipse(cx: 34 + hx, cy: 44 + hy, w: 20, h: 25, angle: 0.38), with: ink)
            ctx.fill(PandaCanvas.tiltedEllipse(cx: 66 + hx, cy: 44 + hy, w: 20, h: 25, angle: -0.38), with: ink)

            // Cheeks
            if mood != .suspicious && mood != .shocked {
                let cheek = GraphicsContext.Shading.color(Theme.pandaCheek.opacity(0.8))
                ctx.fill(PandaCanvas.ellipse(21 + hx, 57 + hy, 10, 5.5), with: cheek)
                ctx.fill(PandaCanvas.ellipse(79 + hx, 57 + hy, 10, 5.5), with: cheek)
            }

            // Eyes
            let ex = hx + glance
            let eyeStroke = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            switch mood {
            case .happy:
                if blink {
                    ctx.stroke(PandaCanvas.line(30 + hx, 45 + hy, 39 + hx, 45 + hy), with: white, style: eyeStroke)
                    ctx.stroke(PandaCanvas.line(61 + hx, 45 + hy, 70 + hx, 45 + hy), with: white, style: eyeStroke)
                } else {
                    ctx.fill(PandaCanvas.ellipse(35 + hx, 44 + hy, 9.5, 9.5), with: white)
                    ctx.fill(PandaCanvas.ellipse(65 + hx, 44 + hy, 9.5, 9.5), with: white)
                    ctx.fill(PandaCanvas.ellipse(35.8 + ex, 44.6 + hy, 5, 5), with: ink)
                    ctx.fill(PandaCanvas.ellipse(64.2 + ex, 44.6 + hy, 5, 5), with: ink)
                    ctx.fill(PandaCanvas.ellipse(37 + ex, 43.2 + hy, 1.8, 1.8), with: white)
                    ctx.fill(PandaCanvas.ellipse(65.4 + ex, 43.2 + hy, 1.8, 1.8), with: white)
                }
            case .suspicious:
                // Narrowed, determined eyes
                ctx.stroke(PandaCanvas.line(29.5 + hx, 43.5 + hy, 40 + hx, 46 + hy), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.line(70.5 + hx, 43.5 + hy, 60 + hx, 46 + hy), with: white, style: eyeStroke)
                ctx.fill(PandaCanvas.ellipse(38 + ex * 0.4, 47.6 + hy, 3.4, 3.4), with: white)
                ctx.fill(PandaCanvas.ellipse(62 + ex * 0.4, 47.6 + hy, 3.4, 3.4), with: white)
            case .shocked:
                ctx.fill(PandaCanvas.ellipse(35 + hx, 44 + hy, 12, 12), with: white)
                ctx.fill(PandaCanvas.ellipse(65 + hx, 44 + hy, 12, 12), with: white)
                ctx.fill(PandaCanvas.ellipse(35 + ex, 44 + hy, 3.2, 3.2), with: ink)
                ctx.fill(PandaCanvas.ellipse(65 + ex, 44 + hy, 3.2, 3.2), with: ink)
            case .proud, .celebrating:
                ctx.stroke(PandaCanvas.arc(30 + hx, 47 + hy, 40 + hx, 47 + hy, bend: -7), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.arc(60 + hx, 47 + hy, 70 + hx, 47 + hy, bend: -7), with: white, style: eyeStroke)
            case .sleeping:
                ctx.stroke(PandaCanvas.arc(30 + hx, 44 + hy, 40 + hx, 44 + hy, bend: 5), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.arc(60 + hx, 44 + hy, 70 + hx, 44 + hy, bend: 5), with: white, style: eyeStroke)
            }

            // Nose
            ctx.fill(PandaCanvas.ellipse(50 + hx + glance * 0.5, 54.5 + hy, 8.5, 5.5), with: ink)

            // Mouth
            let mx = hx + glance * 0.5
            let mouthStroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            switch mood {
            case .happy:
                ctx.stroke(PandaCanvas.arc(45 + mx, 60 + hy, 55 + mx, 60 + hy, bend: 4.5), with: ink, style: mouthStroke)
            case .suspicious:
                ctx.stroke(PandaCanvas.line(45 + mx, 62 + hy, 55 + mx, 60.5 + hy), with: ink, style: mouthStroke)
            case .shocked:
                ctx.fill(PandaCanvas.ellipse(50 + mx, 63 + hy, 6.5, 8), with: ink)
            case .proud:
                ctx.stroke(PandaCanvas.arc(43 + mx, 59.5 + hy, 57 + mx, 59.5 + hy, bend: 7), with: ink, style: mouthStroke)
            case .celebrating:
                var mouth = Path()
                mouth.move(to: CGPoint(x: 43 + mx, y: 59.5 + hy))
                mouth.addQuadCurve(to: CGPoint(x: 57 + mx, y: 59.5 + hy), control: CGPoint(x: 50 + mx, y: 73 + hy))
                mouth.closeSubpath()
                ctx.fill(mouth, with: ink)
            case .sleeping:
                ctx.fill(PandaCanvas.ellipse(50, 61.5, 3.6, 3.6), with: ink)
            }

            // Little extras. Each sits on its own white disc so it reads over any window.
            switch mood {
            case .sleeping:
                ctx.draw(
                    Text("z").font(.system(size: 11, weight: .heavy)).foregroundColor(Color(white: 0.5)),
                    at: CGPoint(x: 84, y: 22)
                )
                ctx.draw(
                    Text("z").font(.system(size: 15, weight: .heavy)).foregroundColor(Color(white: 0.42)),
                    at: CGPoint(x: 92, y: 10)
                )
            case .celebrating:
                let spark = GraphicsContext.Shading.color(Color(white: 0.62))
                ctx.fill(PandaCanvas.sparkle(cx: 8, cy: 34, r: 5), with: spark)
                ctx.fill(PandaCanvas.sparkle(cx: 93, cy: 34, r: 4.5), with: spark)
                ctx.fill(PandaCanvas.sparkle(cx: 50, cy: 4.5, r: 4), with: spark)
            case .shocked, .suspicious:
                let badge = PandaCanvas.ellipse(90, 13 + hy, 17, 17)
                ctx.fill(badge, with: white)
                ctx.stroke(badge, with: ink, lineWidth: 1.6)
                ctx.draw(
                    Text(mood == .shocked ? "!" : "?").font(.system(size: 12, weight: .black)).foregroundColor(Theme.pandaBlack),
                    at: CGPoint(x: 90, y: 13 + hy)
                )
            default:
                break
            }
        }
    }

    // MARK: Path helpers

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }

    static func tiltedEllipse(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat) -> Path {
        let base = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return base.applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: angle))
    }

    static func capsule(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat) -> Path {
        let base = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: w / 2)
        return base.applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: angle))
    }

    static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    }

    /// A gentle curve between two points. Positive bend sags downward, negative arches up.
    static func arc(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, bend: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: (x1 + x2) / 2, y: (y1 + y2) / 2 + bend * 2))
        return p
    }

    /// Four-point star.
    static func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        var p = Path()
        let inner = r * 0.32
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + inner, y: cy - inner))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx + inner, y: cy + inner))
        p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - inner, y: cy + inner))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx - inner, y: cy - inner))
        p.closeSubpath()
        return p
    }
}
