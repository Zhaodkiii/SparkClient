import Foundation

enum PromptLanguage: Sendable {
    case zh
    case en
    case ja
    case ko
    case fr
    case de
    case es
    case pt
    case ar
}

struct PromptLocalizer: Sendable {
    let locale: Locale
    private let l10n: AIPromptL10n

    init(locale: Locale = .current) {
        self.locale = locale
        self.l10n = AIPromptL10n(locale: locale)
    }

    var language: PromptLanguage {
        let languageCode = locale.languageCode?.lowercased() ?? "en"
        let regionCode = locale.regionCode?.uppercased() ?? ""

        if languageCode.hasPrefix("zh") || ["CN", "HK", "MO", "TW", "SG"].contains(regionCode) {
            return .zh
        }

        switch languageCode {
        case "ja":
            return .ja
        case "ko":
            return .ko
        case "fr":
            return .fr
        case "de":
            return .de
        case "es":
            return .es
        case "pt":
            return .pt
        case "ar":
            return .ar
        default:
            return .en
        }
    }

    func chatSystemPrompt() -> String {
        l10n.prompt(
            "ai.prompt.chat.system",
            fallback: "You are Spark Health Assistant. Provide accurate, concise, actionable health guidance and respond in the user's language."
        )
    }

    /// 深度思考：在系统层追加一条简短指令（网关未单独暴露 reasoning 参数时的折中方案）。
    func deepThinkingInstruction() -> String {
        l10n.prompt(
            "ai.prompt.chat.deep_thinking",
            fallback: "Think step by step: briefly outline your reasoning, then give a clear final answer."
        )
    }

    func medicalDocumentExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat(
            "ai.prompt.medical_document.extraction.template",
            fallback: """
            You are a medical document extraction assistant. Extract a structured JSON object from OCR text.
            Return JSON only and include keys:
            {"title":"...","summary":"...","diagnosis":"...","occurredAt":"yyyy-MM-dd","rawType":"...","items":[]}

            OCR text:
            %@
            """,
            ocrText
        )
    }

    func medicalDocumentTypeRecognitionPrompt(ocrText: String) -> String {
        l10n.promptFormat(
            "ai.prompt.medical_document.type_recognition.template",
            fallback: """
            You are a medical document classifier.
            Classify OCR text into one type only: case_document, health_exam_report, medical_report, prescription, medication, medicine_box.
            Return JSON only:
            {"kind":"case_document|health_exam_report|medical_report|prescription|medication|medicine_box","confidence":0.0-1.0,"reason":"..."}

            OCR text:
            %@
            """,
            ocrText
        )
    }

    func medicalCaseExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat(
            "ai.prompt.medical_case.extraction.template",
            fallback: """
            You are a medical case extraction assistant. Output a single JSON object only (no markdown).
            Top-level fields: title (required string), summary, diagnosis, hospitalName, ageAtVisit (string like "28"), occurredAt (ISO or yyyy-MM-dd).
            Optional single objects (omit if unknown): symptom, visit, surgery; optional arrays: followUps, prescriptions, examinationReports.
            Use camelCase keys. symptom/visit/surgery match the app models (e.g. symptom.name, visit.department, surgery.procedureName).
            For medicationPlans in prescriptions: doseValue and everyNDays should be strings (e.g. "1", "0.5", "2").
            OCR text:
            %@
            """,
            ocrText
        )
    }

    func healthExamExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat("ai.prompt.health_exam.extraction.template", fallback: medicalDocumentExtractionPrompt(ocrText: "%@"), ocrText)
    }

    func medicalReportExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat("ai.prompt.medical_report.extraction.template", fallback: medicalDocumentExtractionPrompt(ocrText: "%@"), ocrText)
    }

    func prescriptionExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat("ai.prompt.prescription.extraction.template", fallback: medicalDocumentExtractionPrompt(ocrText: "%@"), ocrText)
    }

    func medicationExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat("ai.prompt.medication.extraction.template", fallback: medicalDocumentExtractionPrompt(ocrText: "%@"), ocrText)
    }

    func nutritionFoodDescriptionPrompt(mealType: NutritionMealType) -> String {
        l10n.promptFormat(
            "ai.prompt.nutrition.food_description.template",
            fallback: """
            You are a food photo description assistant. Describe visible foods, portions, cooking methods, and ingredients in natural language.
            Respond in the user's language. Do not output JSON.
            Meal context: %@
            """,
            L10n.text(mealType.localizationKey)
        )
    }

    func nutritionIntakeExtractionPrompt(mealType: NutritionMealType, sourceText: String) -> String {
        l10n.promptFormat(
            "ai.prompt.nutrition.intake_extraction.template",
            fallback: """
            You are a nutrition intake extraction assistant. Return one JSON object only (camelCase keys, no markdown).
            Top-level keys: title, mealType, confidence, overview, items, intakes, uncertainNotes.
            overview must include energyKcal, proteinG, carbohydrateG, fatG.
            Put uncertain portions or unknown foods into uncertainNotes instead of inventing precise values.
            Default mealType: %@

            Input:
            %@
            """,
            mealType.rawValue,
            sourceText
        )
    }

    func nutritionExtractionRetryCorrectionPrompt(errorSummary: String, outputPreview: String) -> String {
        let notAvailable = nutritionExtractionNotAvailableLabel()
        let template = l10n.prompt(
            "ai.prompt.nutrition.extraction.retry_correction.template",
            fallback: """
            [Retry correction]
            The previous nutrition extraction JSON failed to decode.
            - Error: %@
            - Previous output preview: %@

            Return pure JSON only with camelCase keys. Do not use markdown or explanatory text.
            """
        )
        return String(
            format: template,
            errorSummary.isEmpty ? notAvailable : errorSummary,
            outputPreview.isEmpty ? notAvailable : outputPreview
        )
    }

    func nutritionExtractionNotAvailableLabel() -> String {
        l10n.prompt("ai.prompt.nutrition.extraction.not_available", fallback: "N/A")
    }

    func medicalExtractionRetryCorrectionPrompt(
        kind: MedicalDocumentKind,
        feedback: MedicalExtractionRetryFeedback,
        source: MedicalExtractionPromptSource = .ocrText
    ) -> String {
        switch source {
        case .ocrText:
            return medicalExtractionOCRRetryCorrectionPrompt(kind: kind, feedback: feedback)
        case .visionImage:
            return medicalExtractionVisionRetryCorrectionPrompt(kind: kind, feedback: feedback)
        }
    }

    private func medicalExtractionOCRRetryCorrectionPrompt(
        kind: MedicalDocumentKind,
        feedback: MedicalExtractionRetryFeedback
    ) -> String {
        let kindLabel = localizedMedicalDocumentKindLabel(kind)
        let fieldPath = feedback.fieldPath ?? notAvailableLabel()
        let expectedType = feedback.expectedType ?? notAvailableLabel()
        let actualType = feedback.actualType ?? notAvailableLabel()
        let rawMessage = feedback.rawMessage.isEmpty ? notAvailableLabel() : feedback.rawMessage
        let suggestion = feedback.suggestion ?? notAvailableLabel()

        let template = l10n.prompt(
            "ai.prompt.medical_extraction.retry_correction.template",
            fallback: """
            [Retry correction]
            The previous structured extraction failed:
            - Document type: %@
            - Invalid field: %@
            - Expected type: %@
            - Previous actual type: %@
            - Error: %@
            - Fix suggestion: %@

            Please return pure JSON that follows the original schema, without changing OCR facts.
            Do not return Markdown or explanatory text.
            Use schema-compatible empty values when unknown; for example, use {} for unknown extra and [] for unknown arrays.
            """
        )
        let body = String(
            format: template,
            kindLabel,
            fieldPath,
            expectedType,
            actualType,
            rawMessage,
            suggestion
        )
        return truncatedCorrectionBlock(body, limit: 2500)
    }

    private func medicalExtractionVisionRetryCorrectionPrompt(
        kind: MedicalDocumentKind,
        feedback: MedicalExtractionRetryFeedback
    ) -> String {
        let kindLabel = localizedMedicalDocumentKindLabel(kind)
        let fieldPath = feedback.fieldPath ?? notAvailableLabel()
        let expectedType = feedback.expectedType ?? notAvailableLabel()
        let actualType = feedback.actualType ?? notAvailableLabel()
        let rawMessage = feedback.rawMessage.isEmpty ? notAvailableLabel() : feedback.rawMessage
        let suggestion = feedback.suggestion ?? notAvailableLabel()

        let template: String
        if let dedicated = l10n.promptIfExists("ai.prompt.medical_extraction.vision.retry_correction.template") {
            template = dedicated
        } else {
            let ocrTemplate = l10n.prompt(
                "ai.prompt.medical_extraction.retry_correction.template",
                fallback: """
                [Retry correction]
                The previous structured extraction failed:
                - Document type: %@
                - Invalid field: %@
                - Expected type: %@
                - Previous actual type: %@
                - Error: %@
                - Fix suggestion: %@

                Please return pure JSON that follows the original schema, without changing OCR facts.
                Do not return Markdown or explanatory text.
                Use schema-compatible empty values when unknown; for example, use {} for unknown extra and [] for unknown arrays.
                """
            )
            template = adaptOCRRetryTemplateToVision(ocrTemplate)
        }

        let body = String(
            format: template,
            kindLabel,
            fieldPath,
            expectedType,
            actualType,
            rawMessage,
            suggestion
        )
        return truncatedCorrectionBlock(body, limit: 2500)
    }

    func medicalCaseVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.medical_case.vision.extraction.template",
            ocrKey: "ai.prompt.medical_case.extraction.template",
            englishOCRFallback: """
            You are a medical case extraction assistant. Output a single JSON object only (no markdown).
            Top-level fields: title (required string), summary, diagnosis, hospitalName, ageAtVisit (string like "28"), occurredAt (ISO or yyyy-MM-dd).
            Optional single objects (omit if unknown): symptom, visit, surgery; optional arrays: followUps, prescriptions, examinationReports.
            Use camelCase keys.
            OCR text:
            %@
            """
        )
    }

    func healthExamVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.health_exam.vision.extraction.template",
            ocrKey: "ai.prompt.health_exam.extraction.template",
            englishOCRFallback: medicalDocumentExtractionPrompt(ocrText: "%@")
        )
    }

    func medicalReportVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.medical_report.vision.extraction.template",
            ocrKey: "ai.prompt.medical_report.extraction.template",
            englishOCRFallback: medicalDocumentExtractionPrompt(ocrText: "%@")
        )
    }

    func prescriptionVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.prescription.vision.extraction.template",
            ocrKey: "ai.prompt.prescription.extraction.template",
            englishOCRFallback: medicalDocumentExtractionPrompt(ocrText: "%@")
        )
    }

    func medicationVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.medication.vision.extraction.template",
            ocrKey: "ai.prompt.medication.extraction.template",
            englishOCRFallback: medicalDocumentExtractionPrompt(ocrText: "%@")
        )
    }

    func medicineBoxVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.medicine_box.vision.extraction.template",
            ocrKey: "ai.prompt.medicine_box.extraction.template",
            englishOCRFallback: """
            You are a medication box extraction assistant. Extract an array of medicine box inventory items from OCR text.
            Return JSON array only.
            OCR text:
            %@
            """
        )
    }

    func medicalDocumentVisionExtractionPrompt() -> String {
        visionExtractionPrompt(
            dedicatedKey: "ai.prompt.medical_document.vision.extraction.template",
            ocrKey: "ai.prompt.medical_document.extraction.template",
            englishOCRFallback: """
            You are a medical document extraction assistant. Extract a structured JSON object from OCR text.
            Return JSON only and include keys:
            {"title":"...","summary":"...","diagnosis":"...","occurredAt":"yyyy-MM-dd","rawType":"...","items":[]}

            OCR text:
            %@
            """
        )
    }

    private func visionExtractionPrompt(
        dedicatedKey: String,
        ocrKey: String,
        englishOCRFallback: String
    ) -> String {
        if let dedicated = l10n.promptIfExists(dedicatedKey) {
            return dedicated
        }
        let ocrTemplate = l10n.prompt(ocrKey, fallback: englishOCRFallback)
        return adaptOCRTemplateToVisionPrompt(ocrTemplate)
    }

    private func adaptOCRTemplateToVisionPrompt(_ template: String) -> String {
        var text = stripOCRInputSection(from: template)
        text = replaceOCRSourcePhrases(in: text)
        return "\(visionExtractionHeader())\n\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func adaptOCRRetryTemplateToVision(_ template: String) -> String {
        var text = template
        switch language {
        case .zh:
            text = text
                .replacingOccurrences(of: "原始 OCR 事实", with: "图片中可见事实")
                .replacingOccurrences(of: "OCR 事实", with: "图片中可见事实")
                .replacingOccurrences(of: "OCR事实", with: "图片中可见事实")
        default:
            text = text
                .replacingOccurrences(of: "OCR facts", with: "visible facts in the image(s)")
                .replacingOccurrences(of: "without changing OCR facts", with: "without changing visible facts in the image(s)")
        }
        return text
    }

    private func stripOCRInputSection(from template: String) -> String {
        var text = template
        let tailPatterns = [
            "\n\nOCR文本：\n%@",
            "\nOCR文本：\n%@",
            "\n\nOCR text:\n%@",
            "\nOCR text:\n%@",
            "OCR文本：\n%@",
            "OCR text:\n%@",
            "\nOCR文本：\n",
            "\nOCR text:\n",
        ]
        for pattern in tailPatterns {
            text = text.replacingOccurrences(of: pattern, with: "")
        }
        if text.hasSuffix("\n%@") {
            text = String(text.dropLast(3))
        }
        return text
    }

    private func replaceOCRSourcePhrases(in text: String) -> String {
        switch language {
        case .zh:
            return text
                .replacingOccurrences(of: "纸质病历OCR文本", with: "纸质病历图片")
                .replacingOccurrences(of: "体检报告/OCR文本", with: "体检报告图片")
                .replacingOccurrences(of: "中文OCR文本", with: "中文医疗单据图片")
                .replacingOccurrences(of: "处方 / 医嘱 / OCR 文本", with: "处方/医嘱图片")
                .replacingOccurrences(of: "处方/医嘱/药品说明/OCR文本", with: "处方/医嘱/药品说明图片")
                .replacingOccurrences(of: "药盒、药瓶、泡罩、标签、说明书 OCR 文本", with: "药盒、药瓶、泡罩、标签、说明书图片")
                .replacingOccurrences(of: "从 OCR 文本中", with: "从图片中可见内容")
                .replacingOccurrences(of: "OCR 文本", with: "图片中可见内容")
                .replacingOccurrences(of: "OCR文本", with: "图片中可见内容")
        default:
            return text
                .replacingOccurrences(of: "from OCR text", with: "from visible image content")
                .replacingOccurrences(of: "OCR text", with: "visible image content")
        }
    }

    private func visionExtractionHeader() -> String {
        switch language {
        case .zh:
            return """
            【图片视觉抽取】
            请根据提供的医疗单据图片中可见内容抽取结构化信息，不要编造图片中看不到的内容。
            请保留表格行列对应关系：项目名、结果值、单位、参考范围必须来自同一行或明确关联区域。
            若提供多张图片，请按顺序视为同一份文档的续页并合并抽取。
            """
        default:
            return """
            [Vision extraction]
            Extract structured data only from visible content in the provided medical document image(s). Do not invent hidden facts.
            Preserve table row/column alignment for names, values, units, and reference ranges.
            If multiple images are provided, treat them in order as pages of the same document.
            """
        }
    }

    func medicalExtractionRetrySuggestion(forField field: String) -> String {
        let key = "ai.prompt.medical_extraction.retry.suggestion.\(field)"
        return l10n.prompt(key, fallback: fallbackRetrySuggestion(forField: field))
    }

    func medicalExtractionRetrySuggestionTypeMismatch(expected: String, actual: String) -> String {
        l10n.promptFormat(
            "ai.prompt.medical_extraction.retry.suggestion.type_mismatch",
            fallback: "Expected type %@ but got %@. Return schema-compatible JSON types.",
            expected,
            actual
        )
    }

    private func localizedMedicalDocumentKindLabel(_ kind: MedicalDocumentKind) -> String {
        switch kind {
        case .auto:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.auto", fallback: "auto")
        case .caseDocument:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.case_document", fallback: "case document")
        case .healthExamReport:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.health_exam_report", fallback: "health exam report")
        case .medicalReport:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.medical_report", fallback: "medical report")
        case .prescription:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.prescription", fallback: "prescription")
        case .medicationPlan:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.medication_plan", fallback: "medication plan")
        case .medicineBox:
            return l10n.prompt("ai.prompt.medical_extraction.retry.kind.medicine_box", fallback: "medicine box")
        }
    }

    private func notAvailableLabel() -> String {
        l10n.prompt("ai.prompt.medical_extraction.retry.not_available", fallback: "N/A")
    }

    private func fallbackRetrySuggestion(forField field: String) -> String {
        switch field {
        case "extra":
            return "`extra` must be a JSON object. Use `{}` when unknown. Do not use `\"\"`."
        case "items":
            return "`items` must be an array. Use `[]` when no item is available."
        case "medicines":
            return "`medicines` must be an array of medicine objects."
        case "indicators":
            return "`indicators` must be an array of exam indicator objects."
        case "sortOrder":
            return "Use integer number for `sortOrder`, not string."
        case "date":
            return "Use `yyyy-MM-dd` when visible; otherwise use the schema-compatible empty value."
        case "json_shape":
            return "Return pure JSON only. Do not wrap the payload in Markdown or prose."
        case "generic_type":
            return "Match the schema field types exactly."
        default:
            return "Return JSON that matches the original schema and field types."
        }
    }

    private func truncatedCorrectionBlock(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end])
    }

    func medicineBoxExtractionPrompt(ocrText: String) -> String {
        l10n.promptFormat(
            "ai.prompt.medicine_box.extraction.template",
            fallback: """
            You are a medication box extraction assistant. Extract an array of medicine box inventory items from OCR text.
            Return JSON array only. Each item uses camelCase keys:
            {
              "medicineName":"required if visible",
              "medicineType":"category text such as cold/fever, digestive, cough/throat, chronic, pediatric, or custom",
              "brandName":"brand or trade name",
              "dosageForm":"tablet/capsule/liquid/granule/ointment/injection/etc.",
              "strength":"specification such as 0.5g x 24 tablets",
              "doseUnit":"per-dose unit text when visible, e.g. mg, tablet, sachet",
              "totalQuantity":"package count as text if visible, e.g. 24",
              "expireDate":"yyyy-MM-dd if visible",
              "notes":"usage/storage/label notes",
              "extra":{},
              "sortOrder":"1"
            }
            If multiple medicines are visible, return multiple objects. Do not invent hidden quantities or dates.

            OCR text:
            %@
            """,
            ocrText
        )
    }

    /// 通用任务抽取提示：用于把自然语言整理为“任务生成前的结构化依据”。
    func taskExtractionPrompt(userInput: String) -> String {
        l10n.promptFormat(
            "ai.prompt.task.extraction.template",
            fallback: """
            You are a task extraction assistant.
            Return JSON only with keys:
            {
              "task_type":"medical|exercise|diet|unknown",
              "target_metric":"...",
              "time_info":{"start_time":"ISO8601 or empty","frequency":"...","period":"..."},
              "action":"...",
              "intensity_or_value":"...",
              "confidence":0.0
            }
            Input:
            %@
            """,
            userInput
        )
    }

    func contextSummaryHeader(recordCount: Int) -> String {
        l10n.promptFormat(
            "ai.prompt.context.header",
            fallback: "Recent medical context for member (latest %d records):",
            recordCount
        )
    }

    func contextLine(dateText: String, title: String, summary: String) -> String {
        l10n.promptFormat(
            "ai.prompt.context.line",
            fallback: "- [%@] %@: %@",
            dateText,
            title,
            summary
        )
    }

    func fallbackAssistantText() -> String {
        l10n.prompt(
            "ai.prompt.fallback.assistant",
            fallback: "I can't provide a valid response right now. Please try again shortly."
        )
    }

    func newThreadTitle() -> String {
        l10n.prompt("ai.prompt.thread.new_title", fallback: "New Chat")
    }

    func consentBlockedHint(reason: String?) -> String {
        let defaultReason = l10n.prompt(
            "ai.prompt.consent.blocked.default_reason",
            fallback: "Sensitive information was not forwarded to the model."
        )
        return l10n.promptFormat(
            "ai.prompt.consent.blocked.template",
            fallback: "[ConsentGate] %@",
            reason ?? defaultReason
        )
    }
}
