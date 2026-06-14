import Combine
import Foundation
import UIKit

enum ExternalMedicalDocumentImportSource: String, Sendable {
    case launchOptions
    case sceneConnection
    case applicationOpen
    case onOpenURL
}

struct PendingExternalMedicalDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    let localFile: MedicalUploadLocalFile
    let receivedAt: Date
    let sourceDescription: String?
}

/// App 级外部医疗 PDF 导入协调器：接收、暂存、复制，待主界面就绪后消费。
@MainActor
final class ExternalMedicalDocumentImportCoordinator: ObservableObject {
    @Published private(set) var pendingDocument: PendingExternalMedicalDocument?
    @Published var errorMessage: String?

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    /// 若 URL 属于外部文档导入请求则处理并返回 `true`，否则返回 `false` 交由深链路由。
    @discardableResult
    func tryReceive(_ url: URL, source: ExternalMedicalDocumentImportSource) -> Bool {
        guard Self.shouldHandleAsExternalDocument(url) else { return false }
        receiveExternalURL(url, source: source, sourceDescription: url.absoluteString)
        return true
    }

    func consumeLaunchOptions(_ launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard let url = launchOptions?[.url] as? URL else { return }
        _ = tryReceive(url, source: .launchOptions)
    }

    func consumeConnectionOptions(_ options: UIScene.ConnectionOptions) {
        for context in options.urlContexts {
            _ = tryReceive(context.url, source: .sceneConnection)
        }
    }

    func receiveExternalURL(
        _ url: URL,
        source: ExternalMedicalDocumentImportSource = .applicationOpen,
        sourceDescription: String? = nil
    ) {
        logger.info(
            "收到外部 PDF 打开请求 source=\(source.rawValue) url=\(url.absoluteString)",
            module: .medical
        )
        errorMessage = nil

        let localFile = MedicalUploadLocalFileImportSupport.withSecurityScopedAccess(to: url) { () -> MedicalUploadLocalFile? in
            guard MedicalUploadLocalFileImportSupport.isPDF(url: url, alreadyAccessingSecurityScope: true) else {
                logger.warning("外部文档导入失败 reason=unsupported_type url=\(url.absoluteString)", module: .medical)
                errorMessage = "仅支持导入 PDF 文档"
                return nil
            }

            guard MedicalUploadLocalFileImportSupport.canReadFile(url: url, alreadyAccessingSecurityScope: true) else {
                logger.warning("外部文档导入失败 reason=file_not_found url=\(url.absoluteString)", module: .medical)
                errorMessage = "无法读取该文档，请重新选择文件"
                return nil
            }

            guard let copiedFile = MedicalUploadLocalFileImportSupport.copyToTempFile(
                from: url,
                fileNamePrefix: "external_medical_upload",
                logger: logger,
                alreadyAccessingSecurityScope: true
            ) else {
                logger.error("外部文档导入失败 reason=copy_failed url=\(url.absoluteString)", module: .medical)
                errorMessage = "文档导入失败，请稍后重试"
                return nil
            }

            return copiedFile
        }

        guard let localFile else { return }

        logger.info("外部 PDF 已复制到本地 path=\(localFile.url.path)", module: .medical)
        let document = PendingExternalMedicalDocument(
            id: UUID(),
            localFile: localFile,
            receivedAt: Date(),
            sourceDescription: sourceDescription ?? "\(source.rawValue):\(url.absoluteString)"
        )
        pendingDocument = document
        logger.info("外部 PDF 等待主界面消费 documentID=\(document.id)", module: .medical)
    }

    func consumePendingDocument() -> PendingExternalMedicalDocument? {
        guard let document = pendingDocument else { return nil }
        pendingDocument = nil
        return document
    }

    func clearError() {
        errorMessage = nil
    }

    func clearAll() {
        pendingDocument = nil
        errorMessage = nil
    }

    private static func shouldHandleAsExternalDocument(_ url: URL) -> Bool {
        if url.isFileURL { return true }
        return url.pathExtension.lowercased() == "pdf"
    }
}
