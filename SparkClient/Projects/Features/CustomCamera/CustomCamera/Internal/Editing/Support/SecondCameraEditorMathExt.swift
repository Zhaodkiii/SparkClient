//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension CGFloat {
    func secondCameraEditor_clamp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloat.secondCameraEditor_clamp(self, min: minValue, max: maxValue)
    }

    func secondCameraEditor_clamp01() -> CGFloat {
        return CGFloat.secondCameraEditor_clamp01(self)
    }

    static func secondCameraEditor_random(in range: Range<CGFloat>, choices: UInt) -> CGFloat {
        let rangeSize = range.upperBound - range.lowerBound
        let choice = UInt.random(in: 0..<choices)
        return range.lowerBound + (rangeSize * CGFloat(choice) / CGFloat(choices))
    }

    func secondCameraEditor_lerp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloat.secondCameraEditor_lerp(left: minValue, right: maxValue, alpha: self)
    }

    func secondCameraEditor_inverseLerp(_ minValue: CGFloat, _ maxValue: CGFloat, shouldClamp: Bool = false) -> CGFloat {
        let value = CGFloat.secondCameraEditor_inverseLerp(self, min: minValue, max: maxValue)
        return shouldClamp ? CGFloat.secondCameraEditor_clamp01(value) : value
    }

    static let secondCameraEditor_halfPi: CGFloat = CGFloat.pi * 0.5

    func secondCameraEditor_fuzzyEquals(_ other: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        return abs(self - other) < tolerance
    }

    var secondCameraEditor_square: CGFloat {
        return self * self
    }

    func secondCameraEditor_average(_ other: CGFloat) -> CGFloat {
        (self + other) * 0.5
    }
}

public extension Double {
    func secondCameraEditor_clamp(_ minValue: Double, _ maxValue: Double) -> Double {
        return max(minValue, min(maxValue, self))
    }

    func secondCameraEditor_clamp01() -> Double {
        return secondCameraEditor_clamp(0, 1)
    }

    func secondCameraEditor_lerp(_ minValue: Double, _ maxValue: Double) -> Double {
        return (minValue * (1 - self)) + (maxValue * self)
    }

    func secondCameraEditor_inverseLerp(_ minValue: Double, _ maxValue: Double, shouldClamp: Bool = false) -> Double {
        let value = (self - minValue) / (maxValue - minValue)
        return shouldClamp ? value.secondCameraEditor_clamp01() : value
    }
}

public extension Float {
    func secondCameraEditor_clamp(_ minValue: Float, _ maxValue: Float) -> Float {
        return max(minValue, min(maxValue, self))
    }

    func secondCameraEditor_clamp01() -> Float {
        return secondCameraEditor_clamp(0, 1)
    }

    func secondCameraEditor_lerp(_ minValue: Float, _ maxValue: Float) -> Float {
        return (minValue * (1 - self)) + (maxValue * self)
    }

    func secondCameraEditor_inverseLerp(_ minValue: Float, _ maxValue: Float, shouldClamp: Bool = false) -> Float {
        let value = (self - minValue) / (maxValue - minValue)
        return shouldClamp ? value.secondCameraEditor_clamp01() : value
    }
}

public extension Int {
    func secondCameraEditor_clamp(_ minValue: Int, _ maxValue: Int) -> Int {
        assert(minValue <= maxValue)
        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

public extension UInt {
    func secondCameraEditor_clamp(_ minValue: UInt, _ maxValue: UInt) -> UInt {
        assert(minValue <= maxValue)
        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

public extension UInt64 {
    var secondCameraEditor_asNSNumber: NSNumber {
        NSNumber(value: self)
    }
}
