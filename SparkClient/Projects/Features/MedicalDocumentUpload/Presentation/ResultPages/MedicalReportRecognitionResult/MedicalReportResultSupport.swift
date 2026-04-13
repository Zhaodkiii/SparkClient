import SwiftUI

struct MedicalReportResultSectionCard<Content: View>: View {
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
                    .foregroundStyle(Color(uiColor: .systemTeal))
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

struct MedicalReportResultInfoLine: View {
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

struct MedicalReportResultLocalAttachmentItem: Identifiable {
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

enum MedicalReportResultLocalEditor: Identifiable {
    case report(index: Int, draft: MedicalReportRecognitionDraft)

    var id: String {
        switch self {
        case .report(let index, _):
            return "report-\(index)"
        }
    }
}

enum MedicalReportDraftCategory: String, CaseIterable {
    case laboratory
    case imaging
    case pathology

    var titleKey: String {
        switch self {
        case .laboratory:
            return "medical.upload.result.medical_report.category.laboratory"
        case .imaging:
            return "medical.upload.result.medical_report.category.imaging"
        case .pathology:
            return "medical.upload.result.medical_report.category.pathology"
        }
    }

    var iconName: String {
        switch self {
        case .laboratory:
            return "cross.case"
        case .imaging:
            return "waveform.path.ecg"
        case .pathology:
            return "square.text.square"
        }
    }

    var accentColor: Color {
        switch self {
        case .laboratory:
            return Color(uiColor: .systemBlue)
        case .imaging:
            return Color(uiColor: .systemIndigo)
        case .pathology:
            return Color(uiColor: .systemOrange)
        }
    }

    static func from(_ value: String?) -> MedicalReportDraftCategory {
        let raw = (value ?? "").lowercased()
        if raw.contains("path") || raw.contains("病理") {
            return .pathology
        }
        if raw.contains("image") || raw.contains("影") || raw.contains("ct") || raw.contains("mri") {
            return .imaging
        }
        return .laboratory
    }
}
