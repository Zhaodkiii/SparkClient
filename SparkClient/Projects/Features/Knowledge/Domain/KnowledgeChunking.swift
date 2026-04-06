import Foundation

/// Markdown 正文按标题层级切块，并对超长块再切分（与 Health `KnowledgeWritingView.startEmbedding` 行为对齐，便于嵌入管线复用）。
enum KnowledgeChunking {
    /// 返回可供嵌入 API 批量请求的文本块。
    static func chunksForEmbedding(from content: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var chunks: [String] = []
        var currentChunk = ""
        var currentLevel1: String?
        var currentLevel2: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("#") {
                let level = headerLevel(of: trimmedLine)
                if level == 1 {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    currentLevel1 = trimmedLine
                    currentLevel2 = nil
                    currentChunk = trimmedLine
                    continue
                } else if level == 2 {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    currentLevel2 = trimmedLine
                    if let l1 = currentLevel1 {
                        currentChunk = l1 + "\n" + trimmedLine
                    } else {
                        currentChunk = trimmedLine
                    }
                    continue
                } else if level == 3 {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    var headerContext = ""
                    if let l1 = currentLevel1 { headerContext += l1 + "\n" }
                    if let l2 = currentLevel2 { headerContext += l2 + "\n" }
                    headerContext += trimmedLine
                    currentChunk = headerContext
                    continue
                }
            }
            if currentChunk.isEmpty {
                currentChunk = trimmedLine
            } else {
                currentChunk += "\n" + trimmedLine
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let bodyChunksCount = chunks.filter { chunkHasBody($0) }.count
        if bodyChunksCount > 0 {
            chunks = chunks.filter { chunk in
                let linesInChunk = chunk.components(separatedBy: "\n")
                if let firstLine = linesInChunk.first,
                   firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                    let level = headerLevel(of: firstLine)
                    if (level == 1 || level == 2) && !chunkHasBody(chunk) {
                        return false
                    }
                }
                return true
            }
        }

        let maxChunkLength = 1000
        let overlapMinLength = 200
        let refinedChunks: [String] = chunks.flatMap { chunk -> [String] in
            if chunk.count <= maxChunkLength { return [chunk] }

            let allLines = chunk.components(separatedBy: "\n")
            var headerLines: [String] = []
            var bodyLines: [String] = []
            var reachedBody = false
            for line in allLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !reachedBody && trimmed.hasPrefix("#") {
                    headerLines.append(line)
                } else {
                    reachedBody = true
                    bodyLines.append(line)
                }
            }
            let headerText = headerLines.joined(separator: "\n")

            var segments: [String] = []
            var currentSegmentLines: [String] = []
            var currentLength = 0
            var idx = 0
            func flushSegment() {
                if !currentSegmentLines.isEmpty {
                    let segmentBody = currentSegmentLines.joined(separator: "\n")
                    let segment = headerText.isEmpty ? segmentBody : headerText + "\n" + segmentBody
                    segments.append(segment.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            while idx < bodyLines.count {
                let line = bodyLines[idx]
                let lineLen = line.count + 1
                if currentLength + lineLen <= maxChunkLength {
                    currentSegmentLines.append(line)
                    currentLength += lineLen
                    idx += 1
                } else {
                    flushSegment()
                    var overlapLines: [String] = []
                    var overlapLength = 0
                    for overlapLine in currentSegmentLines.reversed() {
                        overlapLines.insert(overlapLine, at: 0)
                        overlapLength += overlapLine.count + 1
                        if overlapLength >= overlapMinLength { break }
                    }
                    currentSegmentLines = overlapLines
                    currentLength = currentSegmentLines.reduce(0) { $0 + $1.count + 1 }
                }
            }
            flushSegment()
            return segments
        }

        return refinedChunks.filter { $0.isEmpty == false }
    }

    private static func headerLevel(of line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == "#" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func chunkHasBody(_ chunk: String) -> Bool {
        let chunkLines = chunk.components(separatedBy: "\n")
        if let firstLine = chunkLines.first,
           firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            let level = headerLevel(of: firstLine)
            var startIndex = 1
            if level == 1, chunkLines.count > 1,
               chunkLines[1].trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                startIndex = 2
            }
            for i in startIndex..<chunkLines.count {
                let line = chunkLines[i].trimmingCharacters(in: .whitespaces)
                if !line.isEmpty && !line.hasPrefix("#") {
                    return true
                }
            }
            return false
        }
        return true
    }
}
