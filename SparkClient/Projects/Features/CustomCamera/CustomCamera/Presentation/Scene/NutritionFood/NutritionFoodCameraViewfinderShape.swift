import SwiftUI

/// 相机取景框镂空四角边框形状（四个角仅绘制短线+圆角拐角，非完整矩形边框）
struct NutritionFoodCameraViewfinderShape: Shape {
    /// 绘制取景框路径
    /// - Parameter rect: 形状可用完整矩形区域
    /// - Returns: 取景框四角拐角路径
    func path(in rect: CGRect) -> Path {
        // 圆角半径：取宽高最小值的9%作为拐角圆角大小
        let cornerRadius = min(rect.width, rect.height) * 0.09
        // 角上线段长度：取宽高最小值的18%，控制四角伸出短线长度
        let segmentLength = min(rect.width, rect.height) * 0.18

        var path = Path()

        // 左上角拐角绘制
        addCorner(
            to: &path,
            start: CGPoint(x: rect.minX, y: rect.minY + cornerRadius + segmentLength),
            arcCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            arcStart: .degrees(180),
            arcEnd: .degrees(270),
            end: CGPoint(x: rect.minX + cornerRadius + segmentLength, y: rect.minY),
            radius: cornerRadius
        )

        // 右上角拐角绘制
        addCorner(
            to: &path,
            start: CGPoint(x: rect.maxX - cornerRadius - segmentLength, y: rect.minY),
            arcCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            arcStart: .degrees(270),
            arcEnd: .degrees(0),
            end: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius + segmentLength),
            radius: cornerRadius
        )

        // 右下角拐角绘制
        addCorner(
            to: &path,
            start: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - segmentLength),
            arcCenter: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
            arcStart: .degrees(0),
            arcEnd: .degrees(90),
            end: CGPoint(x: rect.maxX - cornerRadius - segmentLength, y: rect.maxY),
            radius: cornerRadius
        )

        // 左下角拐角绘制
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

    /// 单个取景框角绘制工具方法：线段 + 圆角圆弧 + 另一端线段
    /// - Parameters:
    ///   - path: 可变绘图路径引用
    ///   - start: 当前角起始线段端点
    ///   - arcCenter: 圆角圆弧圆心坐标
    ///   - arcStart: 圆弧起始角度
    ///   - arcEnd: 圆弧结束角度
    ///   - end: 当前角结束线段端点
    ///   - radius: 圆角圆弧半径
    private func addCorner(
        to path: inout Path,
        start: CGPoint,
        arcCenter: CGPoint,
        arcStart: Angle,
        arcEnd: Angle,
        end: CGPoint,
        radius: CGFloat
    ) {
        // 移动画笔到当前角起点
        path.move(to: start)
        // 绘制直线至圆弧起始切点
        path.addLine(
            to: CGPoint(
                x: arcCenter.x + cos(CGFloat(arcStart.radians)) * radius,
                y: arcCenter.y + sin(CGFloat(arcStart.radians)) * radius
            )
        )
        // 绘制圆角圆弧拐角，逆时针绘制
        path.addArc(
            center: arcCenter,
            radius: radius,
            startAngle: arcStart,
            endAngle: arcEnd,
            clockwise: false
        )
        // 圆弧结束后，绘制直线到角终点
        path.addLine(to: end)
    }
}
