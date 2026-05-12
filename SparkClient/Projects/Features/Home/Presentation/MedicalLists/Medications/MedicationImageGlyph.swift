import SwiftUI

struct MedicationImageGlyph: View {
    let seed: Int
    let attachment: SparkMedicalSyncAPI.RemoteManagedFile?
    let fileTransferService: FileTransferService

    @State private var localImageURL: URL?
    @State private var isLoadingImage = false

    private var symbolName: String {
        switch seed % 4 {
        case 0:
            return "pills.fill"
        case 1:
            return "capsule.fill"
        case 2:
            return "cross.case.fill"
        default:
            return "medical.thermometer.fill"
        }
    }

    private var symbolColor: Color {
        switch seed % 4 {
        case 0:
            return Color(uiColor: .systemBlue)
        case 1:
            return Color(uiColor: .systemGreen)
        case 2:
            return Color(uiColor: .systemIndigo)
        default:
            return Color(uiColor: .systemTeal)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(symbolColor.opacity(0.16))

            if let localImageURL {
                LocalFileImageThumbnail(url: localImageURL)
                    .clipShape(Circle())
            } else {
                Image(systemName: symbolName)
                    .font(.headline.weight(.semibold))
                    .imageScale(.medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(symbolColor)
            }

            if isLoadingImage {
                ProgressView()
                    .controlSize(.small)
                    .tint(symbolColor)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: attachment?.id) {
            await loadAttachmentThumbnail()
        }
    }

    @MainActor
    private func loadAttachmentThumbnail() async {
        localImageURL = nil
        guard let attachment,
              attachment.isMedicationImageLike,
              let managedFile = attachment.managedFileRecord else {
            return
        }

        if let cachedURL = await fileTransferService.cachedURL(file: managedFile) {
            localImageURL = cachedURL
            return
        }

        isLoadingImage = true
        defer { isLoadingImage = false }

        if let downloadedURL = try? await fileTransferService.download(file: managedFile) {
            localImageURL = downloadedURL
        }
    }
}

enum MedicationImageAttachmentResolver {
    static func firstImageAttachment(
        for plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    ) -> SparkMedicalSyncAPI.RemoteManagedFile? {
        if let medicineBoxID = plan.medicineBox,
           let boxAttachment = medicineBoxesByID[medicineBoxID]?.attachments?.first(where: \.isMedicationImageLike) {
            return boxAttachment
        }
        return plan.attachments?.first(where: \.isMedicationImageLike)
    }
}

extension SparkMedicalSyncAPI.RemoteManagedFile {
    var isMedicationImageLike: Bool {
        let ext = (displayName as NSString).pathExtension.lowercased()
        let mime = mimeType?.lowercased() ?? ""
        return mime.contains("image") || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext)
    }
}
