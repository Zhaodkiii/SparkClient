import Foundation

// MARK: - Codable 解码兼容包装器 Property Wrapper

/// 空对象兼容包装器
/// 适配后端历史接口返回 `{}` 空对象的场景：空字典对象统一解析为 nil；正常结构化对象正常解码为对应模型
@propertyWrapper
struct EmptyObjectAsNil<Value: Codable & Equatable>: Codable, Equatable, @unchecked Sendable {
    /// 包装后的可选模型值
    var wrappedValue: Value?

    init(wrappedValue: Value? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        // 字段为 null，直接赋值 nil
        if singleValueContainer.decodeNil() {
            wrappedValue = nil
            return
        }
        // 字段是空 {} 空字典，视为无数据，赋值 nil
        if let object = try? singleValueContainer.decode([String: String].self),
           object.isEmpty {
            wrappedValue = nil
            return
        }
        // 正常结构化对象，正常解码
        wrappedValue = try Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

/// 灵活可选字符串包装器
/// 兼容后端流式LLM接口脏数据：数字(Int/Double)、字符串、null 均可统一转为 String?，适配 sortOrder 这类字段
@propertyWrapper
struct FlexibleOptionalString: Codable, Sendable, Equatable, Hashable {
    var wrappedValue: String?

    init(wrappedValue: String?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        // 原生字符串直接赋值
        if let stringValue = try? container.decode(String.self) {
            wrappedValue = stringValue
        }
        // 数字转字符串
        else if let intValue = try? container.decode(Int.self) {
            wrappedValue = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            wrappedValue = String(doubleValue)
        }
        // 无法转换则抛出解码异常
        else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "无法将该字段转换为 String")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch wrappedValue {
        case .none:
            try container.encodeNil()
        case .some(let value):
            try container.encode(value)
        }
    }
}

/// 灵活可选浮点数字包装器
/// 兼容字段为数字、数字字符串、null 三种场景，统一输出 Double?
@propertyWrapper
struct FlexibleOptionalDouble: Codable, Sendable, Equatable {
    var wrappedValue: Double?

    init(wrappedValue: Double?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
        }
        // 原生数字直接解析
        else if let value = try? container.decode(Double.self) {
            wrappedValue = value
        }
        // 数字字符串转浮点
        else if let text = try? container.decode(String.self) {
            wrappedValue = Double(text)
        }
        // 无法解析则置空
        else {
            wrappedValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

/// UUID数组默认空值包装器
/// null、普通字符串数组、标准UUID数组统一解析为 [UUID]，解析失败/空值返回空数组
@propertyWrapper
struct DefaultEmptyUUIDArray: Codable, Sendable, Equatable, Hashable {
    var wrappedValue: [UUID]

    init(wrappedValue: [UUID] = []) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = []
        }
        // 标准UUID数组
        else if let uuids = try? container.decode([UUID].self) {
            wrappedValue = uuids
        }
        // 字符串数组，过滤合法UUID
        else if let strings = try? container.decode([String].self) {
            wrappedValue = strings.compactMap(UUID.init(uuidString:))
        }
        // 非法格式返回空数组
        else {
            wrappedValue = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// 用药提醒时间列表兼容包装器
/// 解码兼容历史接口简化格式 `["08:00"]` 字符串数组；编码统一输出标准 ReminderTime 对象数组
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
            // 标准对象格式直接解析
            if let entry = try? container.decode(ReminderTime.self) {
                times.append(entry)
                continue
            }
            // 兼容纯时间字符串格式，自动包装为 ReminderTime
            let raw = try container.decode(String.self)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            times.append(ReminderTime(time: trimmed))
        }
        wrappedValue = times
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        // 编码统一输出完整结构体，不输出纯字符串
        for entry in wrappedValue {
            try container.encode(entry)
        }
    }
}

/// 可空用药提醒时间列表包装器
/// null、空列表统一解析为 nil；有数据时返回 [ReminderTime]，编码空列表输出 null
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
        // 解析出空数组则置为 nil
        wrappedValue = list.wrappedValue.isEmpty ? nil : list.wrappedValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // 无数据/空数组编码输出 null
        guard let wrappedValue, wrappedValue.isEmpty == false else {
            try container.encodeNil()
            return
        }
        try container.encode(CodableReminderTimesList(wrappedValue: wrappedValue))
    }
}

// MARK: - KeyedDecodingContainer 扩展：缺失字段自动兜底兼容
extension KeyedDecodingContainer {
    /// EmptyObjectAsNil 键缺失兜底：字段不存在时返回 nil 包装对象
    func decode<Value: Codable & Equatable>(
        _ type: EmptyObjectAsNil<Value>.Type,
        forKey key: Key
    ) throws -> EmptyObjectAsNil<Value> {
        try decodeIfPresent(type, forKey: key) ?? EmptyObjectAsNil(wrappedValue: nil)
    }

    /// FlexibleOptionalString 缺失键自动返回 nil，避免 keyNotFound 解码崩溃
    func decode(_ type: FlexibleOptionalString.Type, forKey key: Key) throws -> FlexibleOptionalString {
        try decodeIfPresent(type, forKey: key) ?? FlexibleOptionalString(wrappedValue: nil)
    }

    /// FlexibleOptionalDouble 缺失键自动返回 nil
    func decode(_ type: FlexibleOptionalDouble.Type, forKey key: Key) throws -> FlexibleOptionalDouble {
        try decodeIfPresent(type, forKey: key) ?? FlexibleOptionalDouble(wrappedValue: nil)
    }

    /// DefaultEmptyUUIDArray 键缺失返回空数组
    func decode(_ type: DefaultEmptyUUIDArray.Type, forKey key: Key) throws -> DefaultEmptyUUIDArray {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmptyUUIDArray()
    }

    /// CodableReminderTimesList 键缺失返回空提醒列表（接口常省略该字段）
    func decode(_ type: CodableReminderTimesList.Type, forKey key: Key) throws -> CodableReminderTimesList {
        try decodeIfPresent(type, forKey: key) ?? CodableReminderTimesList()
    }

    /// OptionalCodableReminderTimesList 键缺失返回 nil
    func decode(_ type: OptionalCodableReminderTimesList.Type, forKey key: Key) throws -> OptionalCodableReminderTimesList {
        try decodeIfPresent(type, forKey: key) ?? OptionalCodableReminderTimesList(wrappedValue: nil)
    }
}
