import SwiftUI

enum PandaMood: String, CaseIterable, Equatable {
    case happy        // protection on, all good
    case suspicious   // spotted Instagram
    case shocked      // spotted a Short
    case proud        // just closed something
    case celebrating  // you stayed focused
    case sleeping     // protection off
}

/// The panda himself. Drawn in one Canvas pass in a 100 x 100 space, so he is cheap to
/// render and stays sharp at any size.
struct PandaView: View {
    var mood: PandaMood
    var size: CGFloat = 96
    var blink: Bool = false
    var walking: Bool = false
    var facingLeft: Bool = false

    @State private var step = false
    @State private var pop = false

    var body: some View {
        PandaCanvas(mood: mood, blink: blink)
            .frame(width: size, height: size)
            .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            .rotationEffect(.degrees(walking ? (step ? 6 : -6) : 0), anchor: .bottom)
            .offset(y: walking && step ? -size * 0.05 : 0)
            .scaleEffect(pop ? 1.07 : 1, anchor: .bottom)
            .onChange(of: walking) { isWalking in
                if isWalking {
                    withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
                        step = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        step = false
                    }
                }
            }
            .onChange(of: mood) { _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
                }
            }
            .accessibilityLabel(Text("Panda, \(mood.rawValue)"))
    }
}

struct PandaCanvas: View {
    var mood: PandaMood
    var blink: Bool = false

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 100
            ctx.scaleBy(x: scale, y: scale)

            let ink = GraphicsContext.Shading.color(Theme.ink)
            let white = GraphicsContext.Shading.color(Color.white)
            let cream = GraphicsContext.Shading.color(Theme.creamDeep)
            let outline: CGFloat = 2.2

            // Ground shadow
            ctx.fill(PandaCanvas.ellipse(50, 95.5, 50, 6), with: .color(Color.black.opacity(0.10)))

            // Feet
            ctx.fill(PandaCanvas.ellipse(35, 90, 21, 13), with: ink)
            ctx.fill(PandaCanvas.ellipse(65, 90, 21, 13), with: ink)

            // Body
            let body = PandaCanvas.ellipse(50, 76, 52, 38)
            ctx.fill(body, with: white)
            ctx.stroke(body, with: ink, lineWidth: outline)
            ctx.fill(PandaCanvas.ellipse(50, 80, 26, 20), with: cream)

            // Arms
            let armsUp = mood == .celebrating
            let rightUp = mood == .celebrating || mood == .proud
            if armsUp {
                ctx.fill(PandaCanvas.capsule(cx: 21, cy: 58, w: 12, h: 25, angle: -0.75), with: ink)
            } else {
                ctx.fill(PandaCanvas.capsule(cx: 27, cy: 75, w: 12, h: 24, angle: 0.32), with: ink)
            }
            if rightUp {
                ctx.fill(PandaCanvas.capsule(cx: 79, cy: 58, w: 12, h: 25, angle: 0.75), with: ink)
            } else {
                ctx.fill(PandaCanvas.capsule(cx: 73, cy: 75, w: 12, h: 24, angle: -0.32), with: ink)
            }

            // Ears
            ctx.fill(PandaCanvas.ellipse(25, 19, 25, 25), with: ink)
            ctx.fill(PandaCanvas.ellipse(75, 19, 25, 25), with: ink)

            // Head
            let head = PandaCanvas.ellipse(50, 43, 78, 66)
            ctx.fill(head, with: white)
            ctx.stroke(head, with: ink, lineWidth: outline)

            // Eye patches
            ctx.fill(PandaCanvas.tiltedEllipse(cx: 34, cy: 44, w: 20, h: 25, angle: 0.38), with: ink)
            ctx.fill(PandaCanvas.tiltedEllipse(cx: 66, cy: 44, w: 20, h: 25, angle: -0.38), with: ink)

            // Cheeks
            if mood != .suspicious && mood != .shocked {
                let cheek = GraphicsContext.Shading.color(Theme.blush.opacity(0.75))
                ctx.fill(PandaCanvas.ellipse(21, 57, 10, 5.5), with: cheek)
                ctx.fill(PandaCanvas.ellipse(79, 57, 10, 5.5), with: cheek)
            }

            // Eyes
            let eyeStroke = StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            switch mood {
            case .happy:
                if blink {
                    ctx.stroke(PandaCanvas.line(30, 45, 39, 45), with: white, style: eyeStroke)
                    ctx.stroke(PandaCanvas.line(61, 45, 70, 45), with: white, style: eyeStroke)
                } else {
                    ctx.fill(PandaCanvas.ellipse(35, 44, 9.5, 9.5), with: white)
                    ctx.fill(PandaCanvas.ellipse(65, 44, 9.5, 9.5), with: white)
                    ctx.fill(PandaCanvas.ellipse(35.8, 44.6, 5, 5), with: ink)
                    ctx.fill(PandaCanvas.ellipse(64.2, 44.6, 5, 5), with: ink)
                    ctx.fill(PandaCanvas.ellipse(37, 43.2, 1.8, 1.8), with: white)
                    ctx.fill(PandaCanvas.ellipse(65.4, 43.2, 1.8, 1.8), with: white)
                }
            case .suspicious:
                // Narrowed, sideways eyes
                ctx.stroke(PandaCanvas.line(29.5, 43.5, 40, 46), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.line(70.5, 43.5, 60, 46), with: white, style: eyeStroke)
                ctx.fill(PandaCanvas.ellipse(38, 47.6, 3.4, 3.4), with: white)
                ctx.fill(PandaCanvas.ellipse(62, 47.6, 3.4, 3.4), with: white)
            case .shocked:
                ctx.fill(PandaCanvas.ellipse(35, 44, 12, 12), with: white)
                ctx.fill(PandaCanvas.ellipse(65, 44, 12, 12), with: white)
                ctx.fill(PandaCanvas.ellipse(35, 44, 3.2, 3.2), with: ink)
                ctx.fill(PandaCanvas.ellipse(65, 44, 3.2, 3.2), with: ink)
            case .proud, .celebrating:
                ctx.stroke(PandaCanvas.arc(30, 47, 40, 47, bend: -7), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.arc(60, 47, 70, 47, bend: -7), with: white, style: eyeStroke)
            case .sleeping:
                ctx.stroke(PandaCanvas.arc(30, 44, 40, 44, bend: 5), with: white, style: eyeStroke)
                ctx.stroke(PandaCanvas.arc(60, 44, 70, 44, bend: 5), with: white, style: eyeStroke)
            }

            // Nose
            ctx.fill(PandaCanvas.ellipse(50, 54.5, 8.5, 5.5), with: ink)

            // Mouth
            let mouthStroke = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            switch mood {
            case .happy:
                ctx.stroke(PandaCanvas.arc(45, 60, 55, 60, bend: 4.5), with: ink, style: mouthStroke)
            case .suspicious:
                ctx.stroke(PandaCanvas.line(45, 62, 55, 60.5), with: ink, style: mouthStroke)
            case .shocked:
                ctx.fill(PandaCanvas.ellipse(50, 63, 6.5, 8), with: ink)
            case .proud:
                ctx.stroke(PandaCanvas.arc(43, 59.5, 57, 59.5, bend: 7), with: ink, style: mouthStroke)
            case .celebrating:
                var mouth = Path()
                mouth.move(to: CGPoint(x: 43, y: 59.5))
                mouth.addQuadCurve(to: CGPoint(x: 57, y: 59.5), control: CGPoint(x: 50, y: 73))
                mouth.closeSubpath()
                ctx.fill(mouth, with: ink)
            case .sleeping:
                ctx.fill(PandaCanvas.ellipse(50, 61.5, 3.6, 3.6), with: ink)
            }

            // Little extras
            switch mood {
            case .sleeping:
                ctx.draw(
                    Text("z").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink.opacity(0.55)),
                    at: CGPoint(x: 84, y: 22)
                )
                ctx.draw(
                    Text("z").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(Theme.ink.opacity(0.75)),
                    at: CGPoint(x: 92, y: 10)
                )
            case .celebrating:
                let gold = GraphicsContext.Shading.color(Theme.gold)
                ctx.fill(PandaCanvas.sparkle(cx: 8, cy: 34, r: 5), with: gold)
                ctx.fill(PandaCanvas.sparkle(cx: 93, cy: 34, r: 4.5), with: gold)
                ctx.fill(PandaCanvas.sparkle(cx: 50, cy: 4.5, r: 4), with: gold)
            case .shocked:
                ctx.draw(
                    Text("!").font(.system(size: 17, weight: .black, design: .rounded)).foregroundColor(Theme.ink),
                    at: CGPoint(x: 93, y: 14)
                )
            case .suspicious:
                ctx.draw(
                    Text("?").font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(Theme.ink),
                    at: CGPoint(x: 93, y: 14)
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
