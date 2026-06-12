import SwiftUI

struct MedicineBoxRow: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let fileTransferService: FileTransferService

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        box.attachments?.first(where: \.isMedicationImageLike)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MedicationImageGlyph(
                seed: box.id,
                attachment: imageAttachment,
                fileTransferService: fileTransferService
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(medicineBoxStockText(box))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text([medicineStrengthText(box.strength), box.dosageForm.nilIfBlank, medicineTypeText(box.medicineType)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let expireDate = box.expireDate {
                    Text(
                        String(
                            format: L10n.text("home.medical.medicine_box.expire_prefix"),
                            expireDate.formatted(date: .numeric, time: .omitted)
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
