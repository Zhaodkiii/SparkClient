import Foundation

/// 通用编码键：自定义灵活的 Codable 编码/解码键
/// 支持字符串键，用于动态解析 JSON 字段
struct CodableKey: CodingKey {
    /// 字符串键值（JSON 字段名）
    let stringValue: String
    /// 整型键值（极少使用）
    let intValue: Int?

    /// 通过字符串创建编码键
    /// - Parameter stringValue: JSON 字段名称
    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    /// 遵循 CodingKey 协议：字符串构造器
    init?(stringValue: String) {
        self.init(stringValue)
    }

    /// 遵循 CodingKey 协议：整型构造器
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - 便捷方法扩展
extension CodableKey {
    /// 便捷创建编码键（外部简化调用）
    /// - Parameter stringValue: 字段名
    /// - Returns: 编码键实例
    static func key(_ stringValue: String) -> CodableKey {
        CodableKey(stringValue)
    }
}

// MARK: - JSON 解码器扩展
extension JSONDecoder {
    /// 默认全局解码器：项目通用配置
    /// 配置：下划线转驼峰、ISO8601 日期格式
    nonisolated static var `default`: JSONDecoder {
        let decoder = JSONDecoder()
        // JSON 下划线命名 → 模型驼峰命名（例：user_name → userName）
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // 日期解析：使用 ISO8601 标准格式
        decoder.dateDecodingStrategy = .iso8601
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
}
