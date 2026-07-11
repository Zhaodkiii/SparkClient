import Accelerate
import Foundation

/// 余弦相似度（用于查询向量与切块向量的对齐打分）。
nonisolated enum KnowledgeEmbeddingSimilarity {
    nonisolated static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.isEmpty == false else { return 0 }

        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        var sumSqA: Float = 0
        var sumSqB: Float = 0
        vDSP_svesq(a, 1, &sumSqA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &sumSqB, vDSP_Length(b.count))

        let denom = sqrt(sumSqA) * sqrt(sumSqB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
