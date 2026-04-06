import Foundation

/// `[Float]` 与 Core Data `Binary` 互转，供 `KnowledgeChunkEntity.vectorData` 使用。
enum KnowledgeVectorCoding {
    static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    static func decode(_ data: Data) -> [Float]? {
        guard data.count >= MemoryLayout<Float>.size,
              data.count % MemoryLayout<Float>.size == 0 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: buffer.baseAddress, count: count))
        }
    }
}
