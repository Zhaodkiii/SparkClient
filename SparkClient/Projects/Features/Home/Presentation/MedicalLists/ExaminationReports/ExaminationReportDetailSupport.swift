import Foundation

/// 医疗检查明细页共享辅助：统一判断检验/检查标记是否提示异常。
extension String {
    var isPotentiallyAbnormal: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return false }
        return normalized.contains("高")
            || normalized.contains("低")
            || normalized.contains("异常")
            || normalized.contains("阳性")
            || normalized.contains("abnormal")
            || normalized.contains("positive")
            || normalized.contains("high")
            || normalized.contains("low")
            || normalized.contains("↑")
            || normalized.contains("↓")
    }
}
