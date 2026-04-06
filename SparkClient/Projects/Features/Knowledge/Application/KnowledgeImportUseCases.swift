import Foundation
import PDFKit

/// 从用户选择的文件导入纯文本（支持 plain / md / PDF 文本抽取；其余格式首版明确提示不支持）。
struct ImportKnowledgeFromFileUseCase: Sendable {
    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case readFailed(String)
        case pdfNoText

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                return "暂不支持的文件类型：\(ext)"
            case .readFailed(let reason):
                return "读取文件失败：\(reason)"
            case .pdfNoText:
                return "PDF 中未识别到文本。"
            }
        }
    }

    func execute(fileURL: URL) async throws -> String {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "txt", "text", "md", "markdown":
            return try readPlainText(from: fileURL)
        case "pdf":
            return try extractPDFText(from: fileURL)
        default:
            // 首版：仅对无扩展名尝试 UTF-8 文本；否则报错。
            if ext.isEmpty {
                return try readPlainText(from: fileURL)
            }
            throw ImportError.unsupportedType(ext)
        }
    }

    private func readPlainText(from url: URL) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            guard let string = String(data: data, encoding: .utf8) else {
                throw ImportError.readFailed("无法按 UTF-8 解码")
            }
            return string
        } catch {
            throw ImportError.readFailed(error.localizedDescription)
        }
    }

    private func extractPDFText(from url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ImportError.readFailed("无法打开 PDF")
        }
        var full = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let s = page.string {
                full += s + "\n"
            }
        }
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw ImportError.pdfNoText
        }
        return trimmed
    }
}

/// 拉取网页 HTML 并转为可读纯文本（不依赖 SwiftSoup，使用 `NSAttributedString` 解析 HTML）。
struct ImportKnowledgeFromWebUseCase: Sendable {
    enum WebImportError: LocalizedError {
        case invalidURL
        case httpFailed(Int)
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "无效的网址。"
            case .httpFailed(let code):
                return "网页请求失败（\(code)）。"
            case .emptyBody:
                return "页面内容为空。"
            }
        }
    }

    func execute(urlString: String) async throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            throw WebImportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) == false {
            throw WebImportError.httpFailed(http.statusCode)
        }
        guard data.isEmpty == false else {
            throw WebImportError.emptyBody
        }

        if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return try htmlToPlainText(html)
        }
        throw WebImportError.emptyBody
    }

    private func htmlToPlainText(_ html: String) throws -> String {
        guard let data = html.data(using: .utf8) else {
            throw WebImportError.emptyBody
        }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let attr = try NSAttributedString(data: data, options: opts, documentAttributes: nil)
        let plain = attr.string
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard plain.isEmpty == false else {
            throw WebImportError.emptyBody
        }
        return plain
    }
}
