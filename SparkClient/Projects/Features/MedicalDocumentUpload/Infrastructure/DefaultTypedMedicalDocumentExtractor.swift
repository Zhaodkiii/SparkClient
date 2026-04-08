import Foundation
import UniformTypeIdentifiers

struct DefaultTypedMedicalDocumentExtractor: TypedMedicalDocumentExtracting, Sendable {
    let ocrOrchestrator: OCROrchestrator
    let typeResolver: any MedicalDocumentTypeResolving
    let promptFactory: any MedicalPromptBuilding
    let runtimeService: any AIRuntimeServing
    let logger: Logger
    let jsonNormalizer: MedicalDocumentModelJSONNormalizer

    init(
        ocrOrchestrator: OCROrchestrator,
        typeResolver: any MedicalDocumentTypeResolving,
        promptFactory: any MedicalPromptBuilding,
        runtimeService: any AIRuntimeServing,
        logger: Logger = ConsoleLogger(),
        jsonNormalizer: MedicalDocumentModelJSONNormalizer = .init()
    ) {
        self.ocrOrchestrator = ocrOrchestrator
        self.typeResolver = typeResolver
        self.promptFactory = promptFactory
        self.runtimeService = runtimeService
        self.logger = logger
        self.jsonNormalizer = jsonNormalizer
    }

    func extract(
        memberID: Int,
        files: [MedicalUploadLocalFile],
        selectedKind: MedicalDocumentKind
    ) async throws -> MedicalDocumentTypedExtractionOutput {
        let mergedOCR = try await buildMergedOCRText(files: files)
        let resolution = try await typeResolver.resolve(selectedKind: selectedKind, mergedOCRText: mergedOCR)
        let kind = resolution.kind
        let prompt = promptFactory.extractionPrompt(for: MedicalPromptInput(kind: kind, mergedOCRText: mergedOCR))
        let extraction = try await extractTypedResult(kind: kind, prompt: prompt, rawOCRText: mergedOCR)
        let extractedJSON = extraction.json
        let envelope = MedicalDocumentRecognitionEnvelope(
            memberID: memberID,
            sourceFiles: files,
            rawOCRText: mergedOCR,
            typeResolution: resolution
        )
        let preview = """
        {
          "memberID": \(memberID),
          "kind": "\(kind.rawValue)",
          "resolutionSource": "\(resolution.source.rawValue)",
          "confidence": \(String(format: "%.2f", resolution.confidence)),
          "payload": \(extractedJSON)
        }
        """
        logger.info("typed 抽取完成，kind=\(kind.rawValue)", category: "medical_upload")
        return MedicalDocumentTypedExtractionOutput(
            envelope: envelope,
            typedResult: extraction.typed,
            extractedJSON: extractedJSON,
            payloadPreview: preview
        )
    }

    private func extractTypedResult(
        kind: MedicalDocumentKind,
        prompt: String,
        rawOCRText: String
    ) async throws -> (typed: MedicalDocumentTypedResult, json: String) {
        switch kind {
        case .caseDocument:
            let final = try await extractStructured(prompt: prompt, scenario: .medicalCaseExtraction, kindLabel: "case_document", as: DecodedCaseExtractionDTO.self)
            return (.caseDocument(buildCaseDraft(from: final.decoded, rawJSON: final.normalizedJSON)), final.normalizedJSON)
        case .healthExamReport:
            let final = try await extractStructured(prompt: prompt, scenario: .healthExamExtraction, kindLabel: "health_exam_report", as: DecodedHealthExamExtractionDTO.self)
            return (.healthExamReport(buildHealthExamDraft(from: final.decoded, rawOCRText: rawOCRText, rawJSON: final.normalizedJSON)), final.normalizedJSON)
        case .medicalReport, .auto:
            let final = try await extractStructured(prompt: prompt, scenario: .medicalReportExtraction, kindLabel: "medical_report", as: DecodedMedicalReportExtractionDTO.self)
            return (.medicalReport(buildMedicalReportDraft(from: final.decoded, rawJSON: final.normalizedJSON)), final.normalizedJSON)
        case .prescription:
            let final = try await extractStructured(prompt: prompt, scenario: .prescriptionExtraction, kindLabel: "prescription", as: DecodedPrescriptionExtractionDTO.self)
            return (.prescription(buildPrescriptionDraft(from: final.decoded, rawJSON: final.normalizedJSON)), final.normalizedJSON)
        case .medication:
            let final = try await extractStructured(prompt: prompt, scenario: .medicationExtraction, kindLabel: "medication", as: DecodedMedicationExtractionDTO.self)
            return (.medication(buildMedicationDraft(from: final.decoded, rawJSON: final.normalizedJSON)), final.normalizedJSON)
        }
    }

    private func extractStructured<T: Decodable>(
        prompt: String,
        scenario: AIScenario,
        kindLabel: String,
        as type: T.Type
    ) async throws -> StructuredJSONStreamFinal<T> {
        let stream = try await runtimeService.generateTextStream(
            request: AIRuntimeTextRequest(
                scenario: scenario,
                messages: [AIRuntimeMessage(role: .user, content: prompt)],
                reasoning: .disabled
            )
        )
        let decoder = StructuredJSONStreamDecoder<T>(normalizer: jsonNormalizer, logger: logger, kindLabel: kindLabel)
        let final = try await decoder.collect(from: stream)
        if final.decoded == nil {
            logger.warning("文档 DTO 解码失败，kind=\(kindLabel)", category: "medical_upload")
        } else {
            logger.debug("文档 DTO 解码成功，kind=\(kindLabel)", category: "medical_upload")
        }
        return final
    }

    private func buildCaseDraft(from decoded: DecodedCaseExtractionDTO?, rawJSON: String) -> CaseRecognitionDraft {
        .init(
            title: normalizedOptionalText(decoded?.title) ?? "病例文档",
            summary: normalizedOptionalText(decoded?.summary) ?? "",
            diagnosis: normalizedOptionalText(decoded?.diagnosis),
            occurredAt: parseDateString(decoded?.occurredAt),
            rawJSON: rawJSON
        )
    }

    private func buildHealthExamDraft(
        from decoded: DecodedHealthExamExtractionDTO?,
        rawOCRText: String,
        rawJSON: String
    ) -> HealthExamRecognitionDraft {
        guard let decoded else {
            let fallbackItems = parseHealthExamItemsFallback(from: rawJSON)
            return .init(
                institutionName: inferInstitutionName(from: rawOCRText),
                reportNo: nil,
                examDate: nil,
                examType: nil,
                summary: nil,
                items: fallbackItems,
                rawJSON: rawJSON
            )
        }
        return .init(
            institutionName: normalizedOptionalText(decoded.institutionName) ?? inferInstitutionName(from: rawOCRText),
            reportNo: normalizedOptionalText(decoded.reportNo),
            examDate: parseDateString(decoded.examDate),
            examType: normalizedOptionalText(decoded.examType),
            summary: normalizedOptionalText(decoded.summary),
            items: decoded.items.enumerated().map { index, item in
                mapDetailItem(item, fallbackSortOrder: index)
            },
            rawJSON: rawJSON
        )
    }

    private func buildMedicalReportDraft(from decoded: DecodedMedicalReportExtractionDTO?, rawJSON: String) -> MedicalReportRecognitionDraft {
        .init(
            reportType: normalizedOptionalText(decoded?.reportType),
            title: normalizedOptionalText(decoded?.title) ?? "医疗报告",
            hospital: normalizedOptionalText(decoded?.hospital),
            doctor: normalizedOptionalText(decoded?.doctor),
            content: normalizedOptionalText(decoded?.content) ?? "",
            date: parseDateString(decoded?.date),
            details: decoded?.items.enumerated().map { index, item in
                mapMedicalReportDetailItem(item, fallbackSortOrder: index)
            } ?? [],
            rawJSON: rawJSON
        )
    }

    private func buildPrescriptionDraft(from decoded: DecodedPrescriptionExtractionDTO?, rawJSON: String) -> PrescriptionRecognitionDraft {
        .init(
            prescriberName: normalizedOptionalText(decoded?.prescriberName),
            institutionName: normalizedOptionalText(decoded?.institutionName),
            prescribedAt: parseDateString(decoded?.prescribedAt),
            diagnosis: normalizedOptionalText(decoded?.diagnosis),
            batchNo: normalizedOptionalText(decoded?.batchNo),
            medications: decoded?.medications.enumerated().compactMap { index, item in
                mapPrescriptionMedicationItem(item, fallbackSortOrder: index)
            } ?? [],
            rawJSON: rawJSON
        )
    }

    private func buildMedicationDraft(from decoded: DecodedMedicationExtractionDTO?, rawJSON: String) -> MedicationRecognitionDraft {
        .init(
            drugName: normalizedOptionalText(decoded?.drugName) ?? "",
            dosage: normalizedOptionalText(decoded?.dosage),
            frequencyText: normalizedOptionalText(decoded?.frequencyText),
            durationDays: decoded?.durationDays,
            instructions: normalizedOptionalText(decoded?.instructions),
            rawJSON: rawJSON
        )
    }

    private func buildMergedOCRText(files: [MedicalUploadLocalFile]) async throws -> String {
        var chunks: [String] = []
        for (idx, file) in files.enumerated() {
            let ocr = try await recognize(file: file)
            chunks.append("=== File \(idx + 1): \(file.displayName) ===\n\(ocr.text)")
        }
        return chunks.joined(separator: "\n\n")
    }

    private func recognize(file: MedicalUploadLocalFile) async throws -> OCRRecognition {
        if isImage(url: file.url, mimeType: file.mimeType) {
            let data = try Data(contentsOf: file.url)
            return try await ocrOrchestrator.recognize(imageData: data, options: .medicalDefault)
        }
        return try await ocrOrchestrator.recognize(document: file.url, options: .medicalDefault)
    }

    private func isImage(url: URL, mimeType: String?) -> Bool {
        if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
            return true
        }
        if let extType = UTType(filenameExtension: url.pathExtension), extType.conforms(to: .image) {
            return true
        }
        return false
    }

    private func parseDateString(_ value: String?) -> Date? {
        guard let value = normalizedOptionalText(value) else { return nil }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let day = dayFormatter.date(from: value) {
            return day
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func inferInstitutionName(from rawOCRText: String) -> String? {
        let lines = rawOCRText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        for line in lines where line.hasPrefix("===") == false {
            if looksLikeInstitutionName(line) {
                return line
            }
        }
        return lines.first { $0.hasPrefix("===") == false }
    }

    private func looksLikeInstitutionName(_ line: String) -> Bool {
        let keywords = ["医院", "体检", "健康", "门诊", "中心", "clinic", "hospital", "health"]
        let normalized = line.lowercased()
        return keywords.contains { normalized.contains($0.lowercased()) }
    }

    private func mapDetailItem(_ item: DecodedMedicalDetailDTO, fallbackSortOrder: Int) -> HealthExamRecognitionDraft.Item {
        .init(
            category: item.category ?? "",
            subCategory: item.subCategory ?? "",
            itemName: item.itemName ?? "",
            itemCode: item.itemCode ?? "",
            resultValue: item.resultValue ?? "",
            unit: item.unit ?? "",
            referenceRange: item.referenceRange ?? "",
            flag: item.flag ?? "",
            resultAt: parseDateString(item.resultAt),
            modality: item.modality ?? "",
            bodyPart: item.bodyPart ?? "",
            diagnosis: normalizedOptionalText(item.diagnosis),
            extra: item.extra ?? [:],
            sortOrder: item.sortOrder ?? fallbackSortOrder
        )
    }

    private func mapMedicalReportDetailItem(_ item: DecodedMedicalDetailDTO, fallbackSortOrder: Int) -> MedicalReportRecognitionDraft.DetailItem {
        .init(
            category: item.category ?? "",
            subCategory: item.subCategory ?? "",
            itemName: item.itemName ?? "",
            itemCode: item.itemCode ?? "",
            resultValue: item.resultValue ?? "",
            unit: item.unit ?? "",
            referenceRange: item.referenceRange ?? "",
            flag: item.flag ?? "",
            resultAt: parseDateString(item.resultAt),
            modality: item.modality ?? "",
            bodyPart: item.bodyPart ?? "",
            diagnosis: normalizedOptionalText(item.diagnosis),
            extra: item.extra ?? [:],
            sortOrder: item.sortOrder ?? fallbackSortOrder
        )
    }

    private func mapPrescriptionMedicationItem(
        _ item: DecodedPrescriptionMedicationDTO,
        fallbackSortOrder _: Int
    ) -> PrescriptionRecognitionDraft.MedicationItem? {
        guard let name = normalizedOptionalText(item.name) else { return nil }
        return .init(
            name: name,
            specification: normalizedOptionalText(item.specification),
            dosage: normalizedOptionalText(item.dosage),
            frequency: normalizedOptionalText(item.frequency),
            duration: normalizedOptionalText(item.duration),
            instructions: normalizedOptionalText(item.instructions)
        )
    }

    private func parseHealthExamItemsFallback(from rawJSON: String) -> [HealthExamRecognitionDraft.Item] {
        guard
            let data = rawJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["items"] as? [[String: Any]]
        else {
            return []
        }

        return rows.enumerated().map { index, row in
            HealthExamRecognitionDraft.Item(
                category: stringValue(row, keys: ["category"]) ?? "",
                subCategory: stringValue(row, keys: ["subCategory", "sub_category"]) ?? "",
                itemName: stringValue(row, keys: ["itemName", "item_name"]) ?? "",
                itemCode: stringValue(row, keys: ["itemCode", "item_code"]) ?? "",
                resultValue: stringValue(row, keys: ["resultValue", "result_value"]) ?? "",
                unit: stringValue(row, keys: ["unit"]) ?? "",
                referenceRange: stringValue(row, keys: ["referenceRange", "reference_range"]) ?? "",
                flag: stringValue(row, keys: ["flag"]) ?? "",
                resultAt: parseDateString(stringValue(row, keys: ["resultAt", "result_at"])),
                modality: stringValue(row, keys: ["modality"]) ?? "",
                bodyPart: stringValue(row, keys: ["bodyPart", "body_part"]) ?? "",
                diagnosis: normalizedOptionalText(stringValue(row, keys: ["diagnosis"])),
                extra: stringDictionary(row["extra"]),
                sortOrder: intValue(row, keys: ["sortOrder", "sort_order"]) ?? index
            )
        }
    }

    private func stringValue(_ row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let raw = row[key] else { continue }
            switch raw {
            case let value as String:
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { return trimmed }
            case let value as Int:
                return String(value)
            case let value as Double:
                return String(value)
            case let value as Bool:
                return String(value)
            default:
                continue
            }
        }
        return nil
    }

    private func intValue(_ row: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let raw = row[key] else { continue }
            switch raw {
            case let value as Int:
                return value
            case let value as Double:
                return Int(value)
            case let value as String:
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intValue = Int(trimmed) { return intValue }
            default:
                continue
            }
        }
        return nil
    }

    private func stringDictionary(_ raw: Any?) -> [String: String] {
        guard let dictionary = raw as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dictionary {
            switch value {
            case let string as String:
                result[key] = string
            case let int as Int:
                result[key] = String(int)
            case let double as Double:
                result[key] = String(double)
            case let bool as Bool:
                result[key] = String(bool)
            default:
                continue
            }
        }
        return result
    }
}
