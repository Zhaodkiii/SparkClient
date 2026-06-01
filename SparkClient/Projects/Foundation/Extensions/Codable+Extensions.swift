import Foundation

/// 通用编码键：自定义灵活的 Codable 编码/解码键
struct CodableKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension CodableKey {
    static func key(_ stringValue: String) -> CodableKey {
        CodableKey(stringValue)
    }
}

// MARK: - JSON 字符串编解码（工具参数 / 调试 payload）

extension JSONDecoder {
    /// 从 UTF-8 JSON 字符串解码；与 `JSONDecoder.default` 策略一致。
    nonisolated func decode<T: Decodable>(_ type: T.Type, fromJSONString string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Invalid UTF-8 JSON string")
            )
        }
        return try decode(type, from: data)
    }
}

extension JSONEncoder {
    /// 编码为 UTF-8 JSON 字符串；与 `JSONEncoder.default` 策略一致。
    nonisolated func encodeToJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Encoded JSON is not valid UTF-8")
            )
        }
        return text
    }
}

// MARK: - JSON 解码器扩展
extension JSONDecoder {
    /// 默认全局解码器：项目通用配置
    nonisolated static var `default`: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 医疗 API：snake_case → camelCase + 灵活日期（ISO8601 / 部分日期 / Unix 时间戳）。
    nonisolated static var medicalAPI: JSONDecoder {
        let decoder = JSONDecoder.default
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }

    /// 聊天同步 API：snake_case + 毫秒 ISO8601 + Unix 时间戳回退。
    nonisolated static var chatRemote: JSONDecoder {
        let decoder = JSONDecoder.default
        decoder.dateDecodingStrategy = .custom { serializer in
            try ChatCodableDateCodec.decodeRemoteSyncDate(from: serializer)
        }
        return decoder
    }
}

// MARK: - JSON 编码器扩展
extension JSONEncoder {
    /// 默认全局编码器：项目通用配置
    /// 配置：驼峰转下划线、ISO8601 日期格式
    nonisolated static var `default`: JSONEncoder {
        let encoder = JSONEncoder()
        // 模型驼峰命名 → JSON 下划线命名（例：userName → user_name）
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // 日期编码：使用 ISO8601 标准格式
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// 医疗 API 出站 JSON：属性 camelCase → 字段 snake_case（与 Django REST / ``MedicineBoxSerializer`` 等一致）。
    nonisolated static var medicalAPI: JSONEncoder {
        JSONEncoder.default
    }

    /// 聊天同步 API：snake_case + 毫秒 ISO8601（与 Django `DateTimeField` 对齐）。
    nonisolated static var chatRemote: JSONEncoder {
        let encoder = JSONEncoder.default
        encoder.dateEncodingStrategy = .custom { date, serializer in
            var container = serializer.singleValueContainer()
            try container.encode(ISO8601DateFormatter.chatFractional.string(from: date))
        }
        return encoder
    }
}

extension ISO8601DateFormatter {
    /// 与 Django `DateTimeField` 及聊天同步 API 对齐（含毫秒）。
    nonisolated static let chatFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static let chatBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// 聊天相关 JSON 日期编解码（同步 API / Core Data block payload 共用）。
enum ChatCodableDateCodec: Sendable {
    /// 聊天同步与 block payload：毫秒 ISO8601 + Unix 时间戳回退。
    nonisolated static func decodeRemoteSyncDate(from serializer: any Decoder) throws -> Date {
        let container = try serializer.singleValueContainer()
        if let text = try? container.decode(String.self) {
            if let parsed = ISO8601DateFormatter.chatFractional.date(from: text) {
                return parsed
            }
            if let parsed = ISO8601DateFormatter.chatBasic.date(from: text) {
                return parsed
            }
        }
        if let value = try? container.decode(Double.self) {
            let seconds = abs(value) > 100_000_000_000 ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds)
        }
        if let value = try? container.decode(Int.self) {
            let asDouble = Double(value)
            let seconds = abs(asDouble) > 100_000_000_000 ? asDouble / 1000 : asDouble
            return Date(timeIntervalSince1970: seconds)
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported chat date value"
        )
    }
}

// MARK: - Core Data `payloadData`（与聊天同步一致：`chatRemote`）

/// `ChatMessageBlockEntity.payloadData` 编解码门面。
enum ChatMessageBlockCodec: Sendable {
    nonisolated static func encode(_ block: ChatMessageBlock) throws -> Data {
        try JSONEncoder.chatRemote.encode(block)
    }

    nonisolated static func decode(_ data: Data?) -> ChatMessageBlock? {
        guard let data else { return nil }
        return try? JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: data)
    }

    nonisolated static func decodeBlock(from snapshot: ChatMessageBlockRowSnapshot) -> ChatMessageBlock? {
        guard let block = decode(snapshot.payloadData) else { return nil }
        if block.id == snapshot.id { return block }
        return block.replacingIdentity(id: snapshot.id, orderKey: snapshot.orderKey ?? block.orderKey)
    }

    nonisolated static func decodeFailureReason(
        payloadData: Data?,
        kind: ChatMessageBlockKind?
    ) -> String? {
        guard let payloadData else { return "payloadData=nil" }
        do {
            _ = try JSONDecoder.chatRemote.decode(ChatMessageBlock.self, from: payloadData)
            return nil
        } catch {
            let prefix = kind.map { "\($0.rawValue): " } ?? ""
            return "\(prefix)\(CodableDiagnostics.describe(error))"
        }
    }
}

/// 全项目统一的 Codable 解码错误描述。
enum CodableDiagnostics: Sendable {
    nonisolated static func codingPath(_ path: [CodingKey]) -> String {
        guard path.isEmpty == false else { return "<root>" }
        return path.map(\.stringValue).joined(separator: ".")
    }

    nonisolated static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "keyNotFound key=\(key.stringValue) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .typeMismatch(type, context):
            return "typeMismatch type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "valueNotFound type=\(type) path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "dataCorrupted path=\(codingPath(context.codingPath)) debug=\(context.debugDescription)"
        @unknown default:
            return decoding.localizedDescription
        }
    }
}
