import Combine
import Foundation
import UIKit

enum ExternalMedicalDocumentImportSource: String, Sendable {
    case launchOptions
    case sceneConnection
    case applicationOpen
    case onOpenURL

    var launchIntentSource: LaunchIntentSource {
        switch self {
        case .launchOptions:
            return .launchOptions
        case .sceneConnection:
            return .sceneConnection
        case .applicationOpen:
            return .applicationOpen
        case .onOpenURL:
            return .onOpenURL
        }
    }
}

/// 外部医疗 PDF 接收与转换：校验、复制后投递公共 LaunchIntent。
@MainActor
final class ExternalMedicalDocumentImportCoordinator: ObservableObject {
    @Published var errorMessage: String?

    private let logger: Logger
    private let launchIntentCoordinator: LaunchIntentCoordinator

    init(logger: Logger, launchIntentCoordinator: LaunchIntentCoordinator) {
        self.logger = logger
        self.launchIntentCoordinator = launchIntentCoordinator
    }

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
            "ExternalDocument.copy.start source=\(source.rawValue) url=\(url.absoluteString)",
            module: .medical
        )
        errorMessage = nil

        let localFile = MedicalUploadLocalFileImportSupport.withSecurityScopedAccess(to: url) { () -> MedicalUploadLocalFile? in
            guard MedicalUploadLocalFileImportSupport.isPDF(url: url, alreadyAccessingSecurityScope: true) else {
                logger.warning("ExternalDocument.copy.failed reason=unsupported_type url=\(url.absoluteString)", module: .medical)
                errorMessage = "仅支持导入 PDF 文档"
                return nil
            }

            guard MedicalUploadLocalFileImportSupport.canReadFile(url: url, alreadyAccessingSecurityScope: true) else {
                logger.warning("ExternalDocument.copy.failed reason=file_not_found url=\(url.absoluteString)", module: .medical)
                errorMessage = "无法读取该文档，请重新选择文件"
                return nil
            }

            guard let copiedFile = MedicalUploadLocalFileImportSupport.copyToTempFile(
                from: url,
                fileNamePrefix: "external_medical_upload",
                logger: logger,
                alreadyAccessingSecurityScope: true
            ) else {
                logger.error("ExternalDocument.copy.failed reason=copy_failed url=\(url.absoluteString)", module: .medical)
                errorMessage = "文档导入失败，请稍后重试"
                return nil
            }

            return copiedFile
        }

        guard let localFile else { return }

        logger.info("ExternalDocument.copy.success localPath=\(localFile.url.path)", module: .medical)
        launchIntentCoordinator.receive(
            .medicalDocumentUpload(
                ExternalMedicalDocumentUploadIntent(
                    id: UUID(),
                    files: [localFile],
                    receivedAt: Date(),
                    source: source.launchIntentSource,
                    originalURLDescription: sourceDescription ?? "\(source.rawValue):\(url.absoluteString)"
                )
            )
        )
    }

    func clearError() {
        errorMessage = nil
    }

    func clearAll() {
        errorMessage = nil
    }

    private static func shouldHandleAsExternalDocument(_ url: URL) -> Bool {
        if url.isFileURL { return true }
        return url.pathExtension.lowercased() == "pdf"
    }
}
