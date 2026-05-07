import SwiftUI

struct HealthExamResultSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var badgeText: String?
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle, subtitle.isEmpty == false {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if let badgeText, badgeText.isEmpty == false {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemFill))
                        )
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                }
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

struct HealthExamResultInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthExamResultLocalAttachmentItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let mimeType: String?

    init(file: MedicalUploadLocalFile) {
        self.id = file.id
        self.fileURL = file.url
        self.displayName = file.displayName
        self.mimeType = file.mimeType
    }

    var previewInput: FilePreviewInput {
        FilePreviewInput(
            id: id,
            fileURL: fileURL,
            displayName: displayName,
            mimeType: mimeType,
            utTypeIdentifier: nil
        )
    }

    var symbolName: String {
        let ext = (displayName as NSString).pathExtension.lowercased()
        if mimeType?.contains("image") == true || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return "photo"
        }
        if mimeType?.contains("pdf") == true || ext == "pdf" {
            return "doc.richtext"
        }
        return "doc"
    }
}

enum HealthExamResultMode {
    case detail
    case recognition

    var isEditable: Bool {
        switch self {
        case .detail:
            return false
        case .recognition:
            return true
        }
    }
}

enum HealthExamResultAttachmentSource {
    case local([HealthExamResultLocalAttachmentItem])
    case remote([SparkMedicalSyncAPI.RemoteManagedFile], FileTransferService)

    var count: Int {
        switch self {
        case .local(let attachments):
            return attachments.count
        case .remote(let attachments, _):
            return attachments.count
        }
    }
}

enum HealthExamResultSummaryFilter: String, CaseIterable {
    case all
    case normal
    case abnormal

    var titleKey: String {
        switch self {
        case .all:
            return "medical.upload.result.health_exam.summary.total"
        case .normal:
            return "common.normal"
        case .abnormal:
            return "medical.upload.result.health_exam.summary.abnormal"
        }
    }
}

enum HealthExamRiskLevel: String {
    case high
    case mid
    case low
    case normal

    var titleKey: String {
        switch self {
        case .high:
            return "medical.upload.result.health_exam.risk.high"
        case .mid:
            return "medical.upload.result.health_exam.risk.mid"
        case .low:
            return "medical.upload.result.health_exam.risk.low"
        case .normal:
            return "common.normal"
        }
    }

    var tint: Color {
        switch self {
        case .high:
            return Color(uiColor: .systemRed)
        case .mid:
            return Color(uiColor: .systemOrange)
        case .low:
            return Color(uiColor: .systemGreen)
        case .normal:
            return Color(uiColor: .systemTeal)
        }
    }
}

enum HealthExamResultLocalEditor: Identifiable {
    case basicInfo(HealthExamRecognitionDraft)
    case riskItem(index: Int, item: MedicalReportItem)

    var id: String {
        switch self {
        case .basicInfo:
            return "basicInfo"
        case .riskItem(let index, _):
            return "riskItem-\(index)"
        }
    }
}

struct HealthExamRiskDisplayItem: Identifiable {
    let id: String
    let originalIndex: Int
    let item: MedicalReportItem
    let riskLevel: HealthExamRiskLevel

    init(originalIndex: Int, item: MedicalReportItem, riskLevel: HealthExamRiskLevel) {
        self.originalIndex = originalIndex
        self.item = item
        self.riskLevel = riskLevel
        self.id = item.itemName ?? "\(originalIndex)"
    }
}

extension HealthExamRecognitionDraft {
    func replacingBasicInfo(
        institutionName: String?,
        reportNo: String?,
        examDate: String?,
        examType: String?,
        summary: String?
    ) -> HealthExamRecognitionDraft {
        HealthExamRecognitionDraft(
            institutionName: institutionName,
            reportNo: reportNo,
            examDate: examDate,
            examType: examType,
            summary: summary,
            items: items
        )
    }

    func replacingItem(index: Int, item: MedicalReportItem) -> HealthExamRecognitionDraft {
        guard items.indices.contains(index) else { return self }
        var next = items
        next[index] = item
        return HealthExamRecognitionDraft(
            institutionName: institutionName,
            reportNo: reportNo,
            examDate: examDate,
            examType: examType,
            summary: summary,
            items: next
        )
    }
}

extension HealthExamRecognitionDraft {
    init(remoteReport item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) {
        self.init(
            institutionName: item.institutionName,
            reportNo: item.reportNo,
            examDate: item.examDate.map(Self.remoteDateFormatter.string(from:)),
            examType: item.examType.map(String.init),
            summary: item.summary,
            items: (item.medExamDetails ?? []).map(MedicalReportItem.init(remoteDetail:))
        )
    }

    private static let remoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension MedicalReportItem {
    init(remoteDetail detail: SparkMedicalSyncAPI.RemoteMedExamDetail) {
        self.init(
            category: detail.category,
            subCategory: detail.subCategory.nonEmpty,
            itemName: detail.itemName,
            itemCode: detail.itemCode.nonEmpty,
            resultValue: detail.resultValue,
            unit: detail.unit.nonEmpty,
            referenceRange: detail.referenceRange.nonEmpty,
            flag: detail.flag.nonEmpty,
            resultAt: detail.resultAt.map(Self.remoteDateFormatter.string(from:)),
            modality: detail.modality.nonEmpty,
            bodyPart: detail.bodyPart.nonEmpty,
            diagnosis: detail.diagnosis,
            extra: detail.extra,
            sortOrder: "\(detail.sortOrder)"
        )
    }

    private static let remoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension MedicalReportItem {
    var isNormalFlag: Bool {
        let f = (flag ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if f.isEmpty { return true }
        if ["normal", "阴性", "negative", "n", "正常"].contains(f) { return true }
        return false
    }

    var inferredRiskLevel: HealthExamRiskLevel {
        guard isNormalFlag == false else { return .normal }
        let token = [flag, diagnosis, resultValue, referenceRange]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if token.contains("critical") || token.contains("危急") || token.contains("高危") || token.contains("+++") || token.contains("阳性") || token.contains("positive") || token.contains("high") || token.contains("↑") {
            return .high
        }

        if token.contains("abnormal") || token.contains("异常") || token.contains("偏高") || token.contains("偏低") || token.contains("++") || token.contains("+") {
            return .mid
        }

        return .low
    }
}
