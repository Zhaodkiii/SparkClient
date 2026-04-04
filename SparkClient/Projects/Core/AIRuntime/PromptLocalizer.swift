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

    init(locale: Locale = .current) {
        self.locale = locale
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
        switch language {
        case .zh:
            return "你是 Spark 健康助手，请优先提供准确、简洁、可执行的健康建议，并使用中文回复。"
        default:
            return "You are Spark Health Assistant. Provide accurate, concise, actionable health guidance and respond in the user's language."
        }
    }

    func extractionPrompt(ocrText: String) -> String {
        switch language {
        case .zh:
            return """
            你是医疗病历抽取助手。请从 OCR 文本中抽取结构化病历草稿，输出 JSON：
            {"title":"...","summary":"...","diagnosis":"...","occurredAt":"yyyy-MM-dd"}
            要求：
            1) 只输出 JSON，不要额外解释。
            2) summary 不超过120字。
            3) 若日期无法确定，occurredAt 使用今天日期。

            OCR文本：
            \(ocrText)
            """
        default:
            return """
            You are a medical record extraction assistant. Extract a structured draft from OCR text and output JSON only:
            {"title":"...","summary":"...","diagnosis":"...","occurredAt":"yyyy-MM-dd"}
            Rules:
            1) Output JSON only.
            2) Keep summary within 120 characters.
            3) If date is unknown, use today's date for occurredAt.

            OCR text:
            \(ocrText)
            """
        }
    }

    func contextSummaryHeader(recordCount: Int) -> String {
        switch language {
        case .zh:
            return "患者近期病历摘要（最近\(recordCount)条）："
        default:
            return "Recent medical context for patient (latest \(recordCount) records):"
        }
    }

    func contextLine(dateText: String, title: String, summary: String) -> String {
        switch language {
        case .zh:
            return "- [\(dateText)] \(title)：\(summary)"
        default:
            return "- [\(dateText)] \(title): \(summary)"
        }
    }

    func fallbackAssistantText() -> String {
        switch language {
        case .zh:
            return "我现在无法给出有效回复，请稍后重试。"
        default:
            return "I can't provide a valid response right now. Please try again shortly."
        }
    }

    func newThreadTitle() -> String {
        switch language {
        case .zh:
            return "新对话"
        default:
            return "New Chat"
        }
    }

    func extractionFallbackTitle() -> String {
        switch language {
        case .zh:
            return "OCR病历草稿"
        default:
            return "OCR Medical Draft"
        }
    }

    func extractionFallbackSummary() -> String {
        switch language {
        case .zh:
            return "待补充摘要"
        default:
            return "Summary pending completion."
        }
    }

    func consentBlockedHint(reason: String?) -> String {
        switch language {
        case .zh:
            return "[ConsentGate] \(reason ?? "敏感信息未发送到模型。")"
        default:
            return "[ConsentGate] \(reason ?? "Sensitive information was not forwarded to the model.")"
        }
    }
}

