import SwiftUI

/// 医疗文档相机公共形状：外围镂空遮罩、顶部圆角面板、四角取景框。
enum MedicalDocumentCameraShapes {
    static let bottomPanelCornerRadius: CGFloat = 28
    static let maskOpacity: Double = 0.38
}

struct MedicalDocumentCameraOutsideMask: Shape {
    let cutoutRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(
            in: cutoutRect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

struct MedicalDocumentTopRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 参数化四角取景框；圆角与角段长度由 layout profile 提供。
struct MedicalDocumentCameraViewfinderShape: Shape {
    var cornerRadiusFactor: CGFloat = 0.06
    var segmentFactor: CGFloat = 0.14

    func path(in rect: CGRect) -> Path {
        let cornerRadius = min(rect.width, rect.height) * cornerRadiusFactor
        let segmentLength = min(rect.width, rect.height) * segmentFactor

        var path = Path()

        addCorner(
            to: &path,
            start: CGPoint(x: rect.minX, y: rect.minY + cornerRadius + segmentLength),
            arcCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            arcStart: .degrees(180),
            arcEnd: .degrees(270),
            end: CGPoint(x: rect.minX + cornerRadius + segmentLength, y: rect.minY),
            radius: cornerRadius
        )

        addCorner(
            to: &path,
            start: CGPoint(x: rect.maxX - cornerRadius - segmentLength, y: rect.minY),
            arcCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            arcStart: .degrees(270),
            arcEnd: .degrees(0),
            end: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius + segmentLength),
            radius: cornerRadius
        )

        addCorner(
            to: &path,
            start: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - segmentLength),
            arcCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            arcStart: .degrees(0),
            arcEnd: .degrees(90),
            end: CGPoint(x: rect.maxX - cornerRadius - segmentLength, y: rect.maxY),
            radius: cornerRadius
        )

        addCorner(
            to: &path,
            start: CGPoint(x: rect.minX + cornerRadius + segmentLength, y: rect.maxY),
            arcCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
            arcStart: .degrees(90),
            arcEnd: .degrees(180),
            end: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius - segmentLength),
            radius: cornerRadius
        )

        return path
    }

    private func addCorner(
        to path: inout Path,
        start: CGPoint,
        arcCenter: CGPoint,
        arcStart: Angle,
        arcEnd: Angle,
        end: CGPoint,
        radius: CGFloat
    ) {
        path.move(to: start)
        path.addLine(
            to: CGPoint(
                x: arcCenter.x + cos(CGFloat(arcStart.radians)) * radius,
                y: arcCenter.y + sin(CGFloat(arcStart.radians)) * radius
            )
        )
        path.addArc(
            center: arcCenter,
            radius: radius,
            startAngle: arcStart,
            endAngle: arcEnd,
            clockwise: false
        )
        path.addLine(to: end)
    }
}
