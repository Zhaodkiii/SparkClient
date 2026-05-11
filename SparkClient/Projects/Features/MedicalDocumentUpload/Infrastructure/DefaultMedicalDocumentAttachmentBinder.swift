import Foundation

struct DefaultMedicalDocumentAttachmentBinder: MedicalDocumentAttachmentBinding, Sendable {
    let fileAPI: SparkFileAPI
    let logger: Logger

    init(
        fileAPI: SparkFileAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.fileAPI = fileAPI
        self.logger = logger
    }

    func bind(
        uploadedFiles: [UploadedMedicalDocumentFile],
        kind: MedicalDocumentKind,
        receipt: MedicalDocumentSaveReceipt
    ) async {
        for file in uploadedFiles {
            do {
                _ = try await fileAPI.updateBusinessBinding(
                    ManagedFileBusinessUpdateItem(
                        fileID: file.remoteFile.id,
                        businessType: businessType(for: kind),
                        businessID: "\(receipt.recordID)"
                    )
                )
            } catch {
                logger.error("附件绑定失败，fileID=\(file.remoteFile.id), error=\(error.localizedDescription)", module: .medical)
            }
        }
        logger.info("附件绑定流程结束，count=\(uploadedFiles.count)", module: .medical)
    }

    private func businessType(for kind: MedicalDocumentKind) -> String {
        switch kind {
        case .auto:
            return "medical_document"
        case .caseDocument:
            return "medical_case"
        case .healthExamReport:
            return "health_exam_report"
        case .medicalReport:
            return "examination_report"
        case .prescription:
            return "prescription_batch"
        case .medicationPlan:
            return "medication"
        case .medicineBox:
            return "medicine_box"
        }
    }
}
