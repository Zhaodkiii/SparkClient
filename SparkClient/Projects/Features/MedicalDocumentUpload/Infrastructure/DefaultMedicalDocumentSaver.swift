import Foundation

struct DefaultMedicalDocumentSaver: MedicalDocumentSaver, Sendable {
    let medicalDataRepository: any MedicalDataRepository
    let logger: Logger

    init(
        medicalDataRepository: any MedicalDataRepository,
        logger: Logger = ConsoleLogger()
    ) {
        self.medicalDataRepository = medicalDataRepository
        self.logger = logger
    }

    func save(
        memberID: Int,
        result: MedicalDocumentRecognitionResult,
        sourceFiles: [MedicalUploadLocalFile]
    ) async throws -> MedicalDocumentSaveReceipt {
        logger.info(
            "开始保存医疗上传结果，memberID=\(memberID), fileCount=\(sourceFiles.count)",
            category: "medical_upload"
        )
        var snapshot = await medicalDataRepository.loadSnapshot()
        let nextCaseID = (snapshot.medicalCases.map(\.id).max() ?? 0) + 1
        let nextReportID = (snapshot.medicalReports.map(\.id).max() ?? 0) + 1
        let now = Date()

        let medicalCase = MedicalCase(
            id: nextCaseID,
            memberID: memberID,
            recordType: "ai_upload",
            status: 2,
            title: "AI Medical Upload",
            diagnosisSummary: result.extractedSummary ?? "",
            extra: [
                "requested_mode": result.requestedMode?.rawValue ?? "",
                "resolved_mode": result.resolvedMode?.rawValue ?? "",
                "source_file_count": "\(sourceFiles.count)"
            ],
            updatedAt: now
        )
        snapshot.medicalCases.append(medicalCase)

        let medicalReport = MedicalReport(
            id: nextReportID,
            memberID: memberID,
            medicalCaseID: nextCaseID,
            reportType: "ai_extracted_document",
            title: "AI Extracted Document",
            hospital: "",
            doctor: "",
            content: result.extractedJSONString,
            date: now,
            updatedAt: now
        )
        snapshot.medicalReports.append(medicalReport)
        snapshot.updatedAt = now
        try await medicalDataRepository.saveSnapshot(snapshot)
        logger.info("医疗上传结果保存成功，recordID=\(nextCaseID)", category: "medical_upload")

        return MedicalDocumentSaveReceipt(recordID: nextCaseID, savedAt: now, isSuccess: true)
    }
}
