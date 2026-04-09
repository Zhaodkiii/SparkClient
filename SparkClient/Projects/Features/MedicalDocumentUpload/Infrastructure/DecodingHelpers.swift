import Foundation

// MARK: - 灵活字符串值解码
/// 支持从 Int/Double/Bool 自动转换为 String
private struct FlexibleStringValue: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            stringValue = value
        } else if let value = try? container.decode(Int.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Double.self) {
            stringValue = String(value)
        } else if let value = try? container.decode(Bool.self) {
            stringValue = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported value type for string coercion")
            )
        }
    }
}

// MARK: - KeyedDecodingContainer 扩展
extension KeyedDecodingContainer {
    /// 从多个可能的键中解码字符串（支持多种命名风格）
    /// 按顺序尝试，返回第一个非空值
    func decodeFlexibleString(forKeys keys: [Key]) -> String? {
        for key in keys {
            // 尝试直接解码 String
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
            // 尝试从 Int 转换
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
            // 尝试从 Double 转换
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return String(value)
            }
            // 尝试从 Bool 转换
            if let value = try? decodeIfPresent(Bool.self, forKey: key) {
                return String(value)
            }
            // 尝试从 FlexibleStringValue 解码
            if let value = try? decodeIfPresent(FlexibleStringValue.self, forKey: key) {
                let trimmed = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }
        return nil
    }

    /// 从多个可能的键中解码整数（支持字符串转换）
    func decodeFlexibleInt(forKeys keys: [Key]) -> Int? {
        for key in keys {
            // 尝试直接解码 Int
            if let value = try? decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            // 尝试从 String 转换
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intValue = Int(trimmed) {
                    return intValue
                }
            }
            // 尝试从 Double 转换
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return Int(value)
            }
        }
        return nil
    }

    /// 从多个可能的键中解码字符串字典
    func decodeFlexibleStringDictionary(forKeys keys: [Key]) -> [String: String]? {
        for key in keys {
            // 尝试直接解码
            if let value = try? decodeIfPresent([String: String].self, forKey: key) {
                return value
            }
            // 尝试解码值可能为多种类型的字典
            if let value = try? decodeIfPresent([String: FlexibleStringValue].self, forKey: key) {
                return value.mapValues(\.stringValue)
            }
        }
        return nil
    }
}

// MARK: - Date 解码辅助
extension KeyedDecodingContainer {
    /// 从多个可能的日期字符串键中解码 Date
    /// 支持 yyyy-MM-dd 格式
    func decodeFlexibleDate(forKeys keys: [Key]) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for key in keys {
            if let dateString = try? decodeIfPresent(String.self, forKey: key),
               !dateString.isEmpty {
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        return nil
    }
}
