import Foundation

/// JWT 过期时间解析器可能抛出的错误枚举
nonisolated enum JWTExpParserError: Error {
    case invalidJWT               // JWT 格式无效（没有足够的点分隔段）
    case invalidPayloadEncoding   // Payload 的 Base64URL 解码失败
    case invalidJSON              // Payload 无法解析为有效的 JSON 字典
    case missingExp               // JSON 中缺失 'exp'（过期时间）字段或格式不正确
}

/// 解析 JWT 的 Payload（负载）而不验证其签名。
/// 该类仅用于提取过期时间，以便执行 Token 刷新决策逻辑。
nonisolated enum JWTExpParser {
    
    /// 解析出的声明（Claims）结构体
    struct Claims {
        let expDate: Date       // 过期时间
        let subject: String?    // 面向的用户（sub），可选
    }

    /// 解析 JWT 字符串并返回 Claims 声明
    /// - Parameter jwt: 完整的 JWT 字符串
    /// - Returns: 包含过期时间和 sub 的 Claims 结构体
    /// - Throws: `JWTExpParserError` 类型的错误
    static func parseClaims(_ jwt: String) throws -> Claims {
        // JWT 由三部分组成：Header.Payload.Signature，通过点 "." 分割
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw JWTExpParserError.invalidJWT }

        // 获取第二部分，即 Base64URL 编码的 Payload
        let payloadB64 = String(parts[1])
        guard let payloadData = Base64URL.decodeToData(payloadB64) else {
            throw JWTExpParserError.invalidPayloadEncoding
        }

        // 将 Data 解析为 JSON 对象
        let json = try JSONSerialization.jsonObject(with: payloadData, options: [])
        guard let dict = json as? [String: Any] else {
            throw JWTExpParserError.invalidJSON
        }

        // 提取 'exp' 字段值
        let expValue = dict["exp"]
        let expSeconds: TimeInterval?
        
        // 兼容数字类型和字符串类型的 exp 字段
        if let n = expValue as? NSNumber {
            expSeconds = n.doubleValue
        } else if let s = expValue as? String, let d = Double(s) {
            expSeconds = d
        } else {
            expSeconds = nil
        }
        
        // 确保 exp 时间戳有效存在
        guard let expSeconds else { throw JWTExpParserError.missingExp }

        // 提取可选的 'sub' 字段值
        let subject = dict["sub"] as? String
        
        // 将 Unix 时间戳转换成 Date 对象并返回
        return Claims(expDate: Date(timeIntervalSince1970: expSeconds), subject: subject)
    }

    /// Base64URL 编码工具类，用于处理 JWT 专用的 Base64 变体
    private enum Base64URL {
        /// 将 Base64URL 字符串转换回标准的 Data
        static func decodeToData(_ base64url: String) -> Data? {
            // 1. 将 Base64URL 特有的字符替换回标准 Base64 字符
            var base64 = base64url
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")

            // 2. 如果长度不是 4 的倍数，在末尾补充 "=" 填充符
            let remainder = base64.count % 4
            if remainder > 0 {
                base64 += String(repeating: "=", count: 4 - remainder)
            }

            // 3. 使用系统方法进行标准 Base64 解码
            return Data(base64Encoded: base64)
        }
    }
}
