import CoreGraphics

extension CGSize {
    var secondCameraEditor_largerAxis: CGFloat { Swift.max(width, height) }
    var secondCameraEditor_smallerAxis: CGFloat { Swift.min(width, height) }

    static func secondCameraEditor_square(_ edge: CGFloat) -> CGSize {
        CGSize(width: edge, height: edge)
    }
}

extension CGFloat {
    func secondCameraEditor_squareRoot() -> CGFloat { sqrt(self) }
}

extension CGPoint {
    func secondCameraEditor_fuzzyEquals(_ other: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(x - other.x) < tolerance && abs(y - other.y) < tolerance
    }
}
