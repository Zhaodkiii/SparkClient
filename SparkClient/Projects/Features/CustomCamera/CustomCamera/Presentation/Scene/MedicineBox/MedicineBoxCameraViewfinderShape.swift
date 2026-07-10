import SwiftUI

/// 药箱相机四角取景框形状。
struct MedicineBoxCameraViewfinderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius = min(rect.width, rect.height) * 0.09
        let segmentLength = min(rect.width, rect.height) * 0.18

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
