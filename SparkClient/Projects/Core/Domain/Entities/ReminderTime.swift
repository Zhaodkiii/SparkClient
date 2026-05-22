import Foundation

/// 服药提醒时刻（`HH:mm` + 可选剂量），抽取、本地存储与 API 上送/拉取统一使用该结构。
struct ReminderTime: Codable, Equatable, Sendable {
    var time: String
    var dose: Double?
    /// 模型/OCR 输出的非数值剂量文案（如「1滴」），与 `dose` 数值字段并存。
    var doseText: String?

    init(time: String, dose: Double? = nil, doseText: String? = nil) {
        self.time = time.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dose = dose
        self.doseText = doseText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(String.self, forKey: .time)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let numeric = try? container.decode(Double.self, forKey: .dose) {
            dose = numeric
            doseText = nil
        } else if let intValue = try? container.decode(Int.self, forKey: .dose) {
            dose = Double(intValue)
            doseText = nil
        } else if let text = try? container.decode(String.self, forKey: .dose) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            doseText = trimmed.isEmpty ? nil : trimmed
            dose = Double(trimmed)
        } else {
            dose = nil
            doseText = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        if let dose {
            try container.encode(dose, forKey: .dose)
        } else if let doseText {
            try container.encode(doseText, forKey: .dose)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case time
        case dose
    }
}

// MARK: - 列表编解码（仅字段级兼容历史 `"08:00"` 字符串；`ReminderTime` 本身保持标准 Codable）

/// 解码兼容服务端/模型曾输出的 `["08:00"]`；编码统一为 `[{ "time": "08:00", "dose": … }]`。
@propertyWrapper
struct CodableReminderTimesList: Codable, Equatable, Sendable {
    var wrappedValue: [ReminderTime]

    init(wrappedValue: [ReminderTime] = []) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var times: [ReminderTime] = []
        while container.isAtEnd == false {
            if let entry = try? container.decode(ReminderTime.self) {
                times.append(entry)
                continue
            }
            let raw = try container.decode(String.self)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            times.append(ReminderTime(time: trimmed))
        }
        wrappedValue = times
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for entry in wrappedValue {
            try container.encode(entry)
        }
    }
}

@propertyWrapper
struct OptionalCodableReminderTimesList: Codable, Equatable, Sendable {
    var wrappedValue: [ReminderTime]?

    init(wrappedValue: [ReminderTime]? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        let list = try CodableReminderTimesList(from: decoder)
        wrappedValue = list.wrappedValue.isEmpty ? nil : list.wrappedValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        guard let wrappedValue, wrappedValue.isEmpty == false else {
            try container.encodeNil()
            return
        }
        try container.encode(CodableReminderTimesList(wrappedValue: wrappedValue))
    }
}

extension KeyedDecodingContainer {
    /// 键缺失时回落为空列表（API / 流式 JSON 常省略 `reminderTimes`）。
    func decode(_ type: CodableReminderTimesList.Type, forKey key: Key) throws -> CodableReminderTimesList {
        try decodeIfPresent(type, forKey: key) ?? CodableReminderTimesList()
    }

    /// 键缺失时回落为 nil，避免 `@OptionalCodableReminderTimesList` 触发 keyNotFound。
    func decode(_ type: OptionalCodableReminderTimesList.Type, forKey key: Key) throws -> OptionalCodableReminderTimesList {
        try decodeIfPresent(type, forKey: key) ?? OptionalCodableReminderTimesList(wrappedValue: nil)
    }
}

extension Array where Element == ReminderTime {
    /// 抽取/保存前保证为对象列表（供已解码草稿二次规范化）。
    static func normalized(from raw: [ReminderTime]?) -> [ReminderTime] {
        guard let raw else { return [] }
        return raw
            .map { ReminderTime(time: $0.time, dose: $0.dose, doseText: $0.doseText) }
            .filter { $0.time.isEmpty == false }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
