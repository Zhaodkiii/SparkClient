import Foundation

nonisolated enum DeepTutorCaptureCardType: String, Codable, CaseIterable, Sendable {
    case reportPhoto = "report_photo"
    case medicineBoxPhoto = "medicine_box_photo"
    case skinPhoto = "skin_photo"

    var title: String {
        switch self {
        case .reportPhoto:
            return "整理与查看报告数据"
        case .medicineBoxPhoto:
            return "AI智能识别药盒"
        case .skinPhoto:
            return "AI 皮肤拍照辅助"
        }
    }

    var subtitle: String {
        switch self {
        case .reportPhoto:
            return "上传体检报告、化验单、影像报告或 PDF，DeepTutor 将帮助提取关键数值并整理报告信息。"
        case .medicineBoxPhoto:
            return "拍摄药盒正面和关键信息，DeepTutor 将辅助识别药品名称与用药信息。"
        case .skinPhoto:
            return "上传清晰皮肤照片，DeepTutor 将根据图片信息给出记录和就医建议。"
        }
    }

    var supportsFiles: Bool {
        self == .reportPhoto
    }
}

nonisolated struct DeepTutorCaptureCardPayload: Codable, Equatable, Sendable {
    var cardType: DeepTutorCaptureCardType
    var title: String
    var subtitle: String
    var createdAt: Date
    var sourceToolCallID: String?

    init(
        cardType: DeepTutorCaptureCardType,
        title: String? = nil,
        subtitle: String? = nil,
        createdAt: Date = Date(),
        sourceToolCallID: String? = nil
    ) {
        self.cardType = cardType
        self.title = title ?? cardType.title
        self.subtitle = subtitle ?? cardType.subtitle
        self.createdAt = createdAt
        self.sourceToolCallID = sourceToolCallID
    }
}

nonisolated enum DeepTutorCaptureCardAction: String, Sendable {
    case camera
    case photoLibrary
    case files
}
