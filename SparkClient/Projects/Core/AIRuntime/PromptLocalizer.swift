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
