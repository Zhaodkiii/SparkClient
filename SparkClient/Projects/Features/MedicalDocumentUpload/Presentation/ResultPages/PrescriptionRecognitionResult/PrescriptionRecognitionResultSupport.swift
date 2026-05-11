import SwiftUI

struct PrescriptionResultSectionCard<Content: View>: View {
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

struct PrescriptionResultInfoLine: View {
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

struct PrescriptionResultLocalAttachmentItem: Identifiable {
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

enum PrescriptionResultLocalEditor: Identifiable {
    case batch(PrescriptionRecognitionDraft)
    case medication(index: Int, draft: MedicationPlanRecognitionDraft)

    var id: String {
        switch self {
        case .batch:
            return "batch"
        case .medication(let index, _):
            return "medication-\(index)"
        }
    }
}
