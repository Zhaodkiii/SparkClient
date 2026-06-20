import Foundation

struct MemberDefaultBodyMetrics: Sendable, Equatable {
    let heightCm: Double
    let weightKg: Double
}

enum MemberDefaultBodyMetricsEstimator {
    private enum AnthropometricRegionProfile {
        case eastAsia
        case southAsiaMiddleEast
        case west
        case global

        static func resolve(countryCode: String) -> AnthropometricRegionProfile {
            let code = countryCode.uppercased()
            if ["CN", "HK", "MO", "TW", "JP", "KR", "SG", "MY", "TH", "VN", "PH", "ID"].contains(code) {
                return .eastAsia
            }
            if ["IN", "AE", "SA", "IL"].contains(code) {
                return .southAsiaMiddleEast
            }
            if ["US", "CA", "GB", "DE", "FR", "IT", "ES", "PT", "RU", "AU", "NZ", "CH", "SE", "NO", "DK", "IE"].contains(code) {
                return .west
            }
            return .global
        }

        func baseline(sex: String) -> MemberDefaultBodyMetrics {
            switch (self, sex) {
            case (.eastAsia, "male"):
                return .init(heightCm: 170, weightKg: 68)
            case (.eastAsia, "female"):
                return .init(heightCm: 158, weightKg: 55)
            case (.southAsiaMiddleEast, "male"):
                return .init(heightCm: 171, weightKg: 72)
            case (.southAsiaMiddleEast, "female"):
                return .init(heightCm: 159, weightKg: 61)
            case (.west, "male"):
                return .init(heightCm: 178, weightKg: 80)
            case (.west, "female"):
                return .init(heightCm: 165, weightKg: 68)
            case (.global, "male"):
                return .init(heightCm: 172, weightKg: 71)
            case (.global, "female"):
                return .init(heightCm: 160, weightKg: 58)
            case (.eastAsia, _):
                return .init(heightCm: 164, weightKg: 60)
            case (.southAsiaMiddleEast, _):
                return .init(heightCm: 165, weightKg: 65)
            case (.west, _):
                return .init(heightCm: 171, weightKg: 74)
            case (.global, _):
                return .init(heightCm: 166, weightKg: 64)
            }
        }
    }

    static func estimate(
        countryCode: String,
        sex: String,
        ageYears: Int?
    ) -> MemberDefaultBodyMetrics {
        let profile = AnthropometricRegionProfile.resolve(countryCode: countryCode)
        var metrics = profile.baseline(sex: sex.lowercased())

        if let ageYears {
            switch ageYears {
            case ..<18:
                if sex.lowercased() == "male" {
                    metrics = .init(heightCm: min(metrics.heightCm, 165), weightKg: min(metrics.weightKg, 56))
                } else if sex.lowercased() == "female" {
                    metrics = .init(heightCm: min(metrics.heightCm, 158), weightKg: min(metrics.weightKg, 50))
                } else {
                    metrics = .init(heightCm: min(metrics.heightCm, 161), weightKg: min(metrics.weightKg, 53))
                }
            case 40..<60:
                metrics = .init(heightCm: metrics.heightCm - 1, weightKg: metrics.weightKg + 2)
            case 60...:
                metrics = .init(heightCm: metrics.heightCm - 2, weightKg: metrics.weightKg - 1)
            default:
                break
            }
        }

        return .init(
            heightCm: max(145, min(metrics.heightCm, 190)),
            weightKg: max(40, min(metrics.weightKg, 95))
        )
    }
}
