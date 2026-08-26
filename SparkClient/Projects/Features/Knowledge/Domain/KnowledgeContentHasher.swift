import CryptoKit
import Foundation

/// 本地诊断/no-op 判断用哈希；不要求与服务端 `content_hash` 算法字节对齐——
/// 服务端返回的权威 hash 在 ACK/Pull 落地时会直接覆盖本值。
nonisolated enum KnowledgeContentHasher {
    static func hash(title: String, content: String, scope: KnowledgeDocumentScope, boundModelID: String?) -> String {
        let combined = "\(title)\u{1}\(content)\u{1}\(scope.rawValue)\u{1}\(boundModelID ?? "")"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
