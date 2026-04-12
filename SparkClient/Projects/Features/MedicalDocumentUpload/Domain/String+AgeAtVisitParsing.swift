import Foundation

// MARK: - 私有辅助函数

private func firstInteger(in s: String, maxValue: Int = Int.max) -> Int? {
    guard let range = s.range(of: "\\d+", options: .regularExpression) else {
        return nil
    }
    let digits = String(s[range])
    guard let value = Int(digits), value >= 0, value <= maxValue else {
        return nil
    }
    return value
}

private func firstDouble(in s: String) -> Double? {
    // 支持 "1", "0.5", "2.0", "1.5g" 等格式，提取第一个数字（包括小数）
    guard let range = s.range(of: "\\d+\\.?\\d*", options: .regularExpression) else {
        return nil
    }
    let numberStr = String(s[range])
    return Double(numberStr)
}

// MARK: - String? 扩展（OCR 脏数据解析）

extension Optional where Wrapped == String {
    /// 将 OCR/模型输出的年龄字符串解析为 `age_at_visit` 用整数。
    ///
    /// - 支持：`"28"`、`"28岁"`、`"年龄28"`、`"28;27"`（优先取分号或斜杠前一段中的首个数字）、`"28/27"` 等。
    /// - 若首选片段中无数字，则在整串中查找**第一个**连续数字序列。
    /// - 解析失败或年龄不在 `0...maxAge` 时返回 `nil`。
    func parsedAsAgeAtVisitInteger(maxAge: Int = 150) -> Int? {
        guard let raw = self?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        let headSegment = raw.split { $0 == ";" || $0 == "/" }.map(String.init).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw

        if let v = firstInteger(in: headSegment, maxValue: maxAge) {
            return v
        }
        return firstInteger(in: raw, maxValue: maxAge)
    }

    /// 将 OCR/模型输出的剂量字符串解析为 `dose_value` 用 Double。
    ///
    /// - 支持：`"1"`, `"0.5"`, `"2.0"`, `"1.5g"`, `"1g/次"`, `"1片"` 等。
    /// - 提取字符串中**第一个**数字（包括小数）。
    /// - 解析失败时返回 `nil`。
    func parsedAsDoseValue() -> Double? {
        guard let raw = self?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        return firstDouble(in: raw)
    }

    /// 将 OCR/模型输出的频次次数字符串解析为 `times_per_period` 用 Int。
    ///
    /// - 支持：`"1"`, `"2"`, `"3次"`, `"每日2次"`, `"2次/日"` 等。
    /// - 提取字符串中**第一个**数字序列。
    /// - 解析失败或数值不在 `0...maxTimes` 时返回 `nil`。
    func parsedAsTimesPerPeriod(maxTimes: Int = 100) -> Int? {
        guard let raw = self?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        return firstInteger(in: raw, maxValue: maxTimes)
    }

    /// 将 OCR/模型输出的天数字符串解析为 `duration_days` 用 Int。
    ///
    /// - 支持：`"7"`, `"7天"`, `"七日"`, `"一周"`（中文数字暂不支持，只提取阿拉伯数字）。
    /// - 提取字符串中**第一个**数字序列。
    /// - 解析失败或数值不在 `0...maxDays` 时返回 `nil`。
    func parsedAsDurationDays(maxDays: Int = 3650) -> Int? {
        guard let raw = self?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        return firstInteger(in: raw, maxValue: maxDays)
    }

    /// 将模型输出的排序序号（多为 `"4"` 字符串，也可能为纯数字文本）解析为 `sort_order` 用 Int。
    ///
    /// - 支持：`"4"`、`" 4 "`、`"12"`；解析失败或越界时返回 `nil`。
    func parsedAsSortOrderInt(maxValue: Int = 1_000_000) -> Int? {
        guard let raw = self?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return nil
        }
        if let v = Int(raw), v >= 0, v <= maxValue {
            return v
        }
        return firstInteger(in: raw, maxValue: maxValue)
    }
}

// MARK: - KeyedDecodingContainer（sortOrder 兼容 Int / String）

extension KeyedDecodingContainer {
    /// 解码 `sortOrder`：JSON 可能是整数或字符串（LLM 常输出 `"4"`）。
    func decodeFlexibleSortOrderIfPresent(forKey key: Key) -> String? {
        guard contains(key) else { return nil }
        if let s = try? decode(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let i = try? decode(Int.self, forKey: key) {
            return String(i)
        }
        return nil
    }
}
