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
            Classify OCR text into one type only: case_document, health_exam_report, medical_report, prescription, medication.
            Return JSON only:
            {"kind":"case_document|health_exam_report|medical_report|prescription|medication","confidence":0.0-1.0,"reason":"..."}

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
            Optional single objects (omit if unknown): symptom, visit, surgery; optional arrays: followUps, prescriptionBatches, examinationReports.
            Use camelCase keys. symptom/visit/surgery match the app models (e.g. symptom.name, visit.department, surgery.procedureName).
            For medications in prescriptionBatches: doseValue, timesPerPeriod, durationDays should be strings (e.g. "1", "0.5", "2", "7").
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

