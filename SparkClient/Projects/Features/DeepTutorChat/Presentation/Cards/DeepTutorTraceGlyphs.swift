import SwiftUI

/// Web `TracePanels` 手绘风格图标，用于活动轨迹行与面板标题。
enum DeepTutorTraceGlyph: String {
    case reasoning
    case responded
    case globe
    case speech
    case knowledge
    case command
    case tool
    case error

    @ViewBuilder
    var view: some View {
        switch self {
        case .reasoning:
            DeepTutorReasoningGlyph()
        case .responded:
            DeepTutorRespondedGlyph()
        case .globe:
            DeepTutorGlobeGlyph()
        case .speech:
            DeepTutorSpeechGlyph()
        case .knowledge:
            DeepTutorKnowledgeGlyph()
        case .command:
            DeepTutorCommandGlyph()
        case .tool:
            DeepTutorToolGlyph()
        case .error:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    static func from(iconKey: String) -> DeepTutorTraceGlyph {
        DeepTutorTraceGlyph(rawValue: iconKey) ?? .tool
    }
}

struct DeepTutorReasoningGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            var transform = CGAffineTransform(translationX: 12, y: 12)
                .rotated(by: 12 * .pi / 180)
                .translatedBy(x: -12, y: -12)
            let rays: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 7.5)),
                (CGPoint(x: 12, y: 22), CGPoint(x: 12, y: 16.5)),
                (CGPoint(x: 2, y: 12), CGPoint(x: 7.5, y: 12)),
                (CGPoint(x: 22, y: 12), CGPoint(x: 16.5, y: 12)),
                (CGPoint(x: 4.6, y: 4.6), CGPoint(x: 8.4, y: 8.4)),
                (CGPoint(x: 19.4, y: 19.4), CGPoint(x: 15.6, y: 15.6)),
                (CGPoint(x: 4.2, y: 19.8), CGPoint(x: 8.2, y: 15.8)),
                (CGPoint(x: 19.8, y: 4.2), CGPoint(x: 15.8, y: 8.2)),
                (CGPoint(x: 7.6, y: 2.3), CGPoint(x: 9, y: 5.8)),
                (CGPoint(x: 16.4, y: 2.3), CGPoint(x: 15, y: 5.8)),
                (CGPoint(x: 7.6, y: 21.7), CGPoint(x: 9, y: 18.2)),
                (CGPoint(x: 16.4, y: 21.7), CGPoint(x: 15, y: 18.2)),
            ]
            for (start, end) in rays {
                var path = Path()
                path.move(to: start.applying(transform))
                path.addLine(to: end.applying(transform))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorRespondedGlyph: View {
    var size: CGFloat = 22
    var body: some View {
        Canvas { context, _ in
            var transform = CGAffineTransform(translationX: 12, y: 12)
                .rotated(by: 8 * .pi / 180)
                .translatedBy(x: -12, y: -12)
            var center = Path(ellipseIn: CGRect(x: 10.2, y: 10.2, width: 3.6, height: 3.6))
            center = center.applying(transform)
            context.fill(center, with: .foreground)
            let rays: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 12, y: 4.5), CGPoint(x: 12, y: 8)),
                (CGPoint(x: 12, y: 19.5), CGPoint(x: 12, y: 16)),
                (CGPoint(x: 4.5, y: 12), CGPoint(x: 8, y: 12)),
                (CGPoint(x: 19.5, y: 12), CGPoint(x: 16, y: 12)),
                (CGPoint(x: 6, y: 6), CGPoint(x: 8.6, y: 8.6)),
                (CGPoint(x: 18, y: 18), CGPoint(x: 15.4, y: 15.4)),
            ]
            for (start, end) in rays {
                var path = Path()
                path.move(to: start.applying(transform))
                path.addLine(to: end.applying(transform))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorGlobeGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            var transform = CGAffineTransform(translationX: 12, y: 12)
                .rotated(by: -6 * .pi / 180)
                .translatedBy(x: -12, y: -12)
            var circle = Path(ellipseIn: CGRect(x: 5.8, y: 5.8, width: 12.4, height: 12.4))
            circle = circle.applying(transform)
            context.stroke(circle, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var meridian1 = Path()
            meridian1.move(to: CGPoint(x: 12, y: 5.8).applying(transform))
            meridian1.addQuadCurve(to: CGPoint(x: 12, y: 18.2).applying(transform), control: CGPoint(x: 7, y: 12).applying(transform))
            var meridian2 = Path()
            meridian2.move(to: CGPoint(x: 12, y: 5.8).applying(transform))
            meridian2.addQuadCurve(to: CGPoint(x: 12, y: 18.2).applying(transform), control: CGPoint(x: 17, y: 12).applying(transform))
            var latitude = Path()
            latitude.move(to: CGPoint(x: 6, y: 10.3).applying(transform))
            latitude.addLine(to: CGPoint(x: 18, y: 10.3).applying(transform))
            context.stroke(meridian1, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            context.stroke(meridian2, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            context.stroke(latitude, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorSpeechGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            var bubble = Path()
            bubble.move(to: CGPoint(x: 6, y: 16.2))
            bubble.addQuadCurve(to: CGPoint(x: 19.5, y: 11.4), control: CGPoint(x: 19.5, y: 6.5))
            bubble.addQuadCurve(to: CGPoint(x: 6, y: 16.2), control: CGPoint(x: 4.5, y: 6.5))
            bubble.addLine(to: CGPoint(x: 8.6, y: 19.4))
            bubble.addLine(to: CGPoint(x: 9, y: 16))
            bubble.closeSubpath()
            context.stroke(bubble, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            for x in [9.0, 12.0, 15.0] {
                let dot = Path(ellipseIn: CGRect(x: x - 1, y: 10, width: 2, height: 2))
                context.fill(dot, with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorKnowledgeGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            var top = Path()
            top.move(to: CGPoint(x: 4.5, y: 9))
            top.addQuadCurve(to: CGPoint(x: 19.5, y: 9), control: CGPoint(x: 12, y: 5))
            top.addQuadCurve(to: CGPoint(x: 4.5, y: 9), control: CGPoint(x: 12, y: 13))
            context.stroke(top, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            var shelf = Path()
            shelf.move(to: CGPoint(x: 5.2, y: 13.4))
            shelf.addQuadCurve(to: CGPoint(x: 18.8, y: 13.4), control: CGPoint(x: 12, y: 17))
            context.stroke(shelf, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            let dot = Path(ellipseIn: CGRect(x: 10.9, y: 7.9, width: 2.2, height: 2.2))
            context.fill(dot, with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorCommandGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            var transform = CGAffineTransform(translationX: 12, y: 12)
                .rotated(by: -3 * .pi / 180)
                .translatedBy(x: -12, y: -12)
            var chevron = Path()
            chevron.move(to: CGPoint(x: 6, y: 8).applying(transform))
            chevron.addLine(to: CGPoint(x: 10, y: 12).applying(transform))
            chevron.addLine(to: CGPoint(x: 6, y: 16).applying(transform))
            var line = Path()
            line.move(to: CGPoint(x: 12.5, y: 16).applying(transform))
            line.addLine(to: CGPoint(x: 18, y: 16).applying(transform))
            context.stroke(chevron, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DeepTutorToolGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, _ in
            let center = Path(ellipseIn: CGRect(x: 9.6, y: 10.6, width: 4.8, height: 4.8))
            context.stroke(center, with: .foreground, style: StrokeStyle(lineWidth: 1.5))
            var orbit = Path()
            orbit.addArc(center: CGPoint(x: 12, y: 12), radius: 10.5, startAngle: .degrees(200), endAngle: .degrees(20), clockwise: false)
            context.stroke(orbit, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            let satellite = Path(ellipseIn: CGRect(x: 19, y: 12.5, width: 3, height: 3))
            context.fill(satellite, with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
