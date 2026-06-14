import Foundation
import UniformTypeIdentifiers

/// 医疗文档上传共用的本地文件导入工具：校验 PDF、复制安全作用域 URL 到临时目录。
enum MedicalUploadLocalFileImportSupport {
    static func isPDF(url: URL) -> Bool {
        isPDF(url: url, alreadyAccessingSecurityScope: false)
    }

    static func isPDF(url: URL, alreadyAccessingSecurityScope: Bool) -> Bool {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            return true
        }
        if url.pathExtension.lowercased() == "pdf" {
            return true
        }
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let type = values.contentType,
           type.conforms(to: .pdf) {
            return true
        }
        return false
    }

    static func canReadFile(url: URL, alreadyAccessingSecurityScope: Bool) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func withSecurityScopedAccess<T>(
        to url: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }

    static func copyToTempFile(
        from url: URL,
        fileNamePrefix: String = "medical_upload",
        logger: Logger
    ) -> MedicalUploadLocalFile? {
        copyToTempFile(
            from: url,
            fileNamePrefix: fileNamePrefix,
            logger: logger,
            alreadyAccessingSecurityScope: false
        )
    }

    static func copyToTempFile(
        from url: URL,
        fileNamePrefix: String = "medical_upload",
        logger: Logger,
        alreadyAccessingSecurityScope: Bool
    ) -> MedicalUploadLocalFile? {
        if alreadyAccessingSecurityScope == false {
            return withSecurityScopedAccess(to: url) {
                copyToTempFile(
                    from: url,
                    fileNamePrefix: fileNamePrefix,
                    logger: logger,
                    alreadyAccessingSecurityScope: true
                )
            }
        }

        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileNamePrefix)_\(UUID().uuidString).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
            let mimeType = ext.lowercased() == "pdf"
                ? "application/pdf"
                : UTType(filenameExtension: ext)?.preferredMIMEType
            return MedicalUploadLocalFile(
                url: target,
                displayName: url.lastPathComponent,
                mimeType: mimeType
            )
        } catch {
            logger.error("复制文件到临时目录失败：\(error.localizedDescription)", module: .medical)
            return nil
        }
    }
}
