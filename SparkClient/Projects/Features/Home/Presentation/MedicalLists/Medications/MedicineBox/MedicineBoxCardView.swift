import SwiftUI

/// 药箱双列网格中的药品卡片
struct MedicineBoxCardView: View {
    let box: SparkMedicalSyncAPI.RemoteMedicineBox
    let fileTransferService: FileTransferService

    private var imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile? {
        box.attachments?.first(where: \.isMedicationImageLike)
    }

    private var statusBadge: MedicineBoxStatusBadge.Resolved? {
        MedicineBoxStatusBadge.resolve(for: box)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 120)
                    .overlay {
                        MedicationImageGlyph(
                            seed: box.id,
                            attachment: imageAttachment,
                            fileTransferService: fileTransferService
                        )
                        .frame(width: 120, height: 120)
                    }

                if let statusBadge {
                    Text(statusBadge.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            statusBadge.color.opacity(statusBadge.kind == .expired ? 0.55 : 1),
                            in: Capsule()
                        )
                        .padding(8)
                }
            }

            Text(box.medicineName.nilIfBlank ?? L10n.text("home.medical.medicine_box.unnamed"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(specLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Spacer()
                Text(L10n.text("home.medical.family_cabinet.view_more"))
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color(uiColor: .systemPurple))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private var specLine: String {
        let strength = box.strength.nilIfBlank ?? ""
        let qty: String
        if let total = box.totalQuantity {
            qty = " ×\(total.formatted(.number.precision(.fractionLength(0...2))))"
        } else {
            qty = ""
        }
        return strength.isEmpty ? qty.trimmingCharacters(in: .whitespaces) : "\(strength)\(qty)"
    }
}

/// 药箱卡片角标：过期 / 临期 / 库存不足
enum MedicineBoxStatusBadge {
    enum Kind {
        case expired
        case expiringSoon
        case lowStock
    }

    struct Resolved {
        let kind: Kind
        let text: String
        let color: Color
    }

    static func resolve(for box: SparkMedicalSyncAPI.RemoteMedicineBox) -> Resolved? {
        if let expire = box.expireDate {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let expireDay = calendar.startOfDay(for: expire)
            if expireDay < today {
                return Resolved(
                    kind: .expired,
                    text: L10n.text("home.medical.family_cabinet.badge.expired"),
                    color: Color(uiColor: .systemGray)
                )
            }
            if let soon = calendar.date(byAdding: .day, value: 30, to: today), expireDay <= soon {
                return Resolved(
                    kind: .expiringSoon,
                    text: L10n.text("home.medical.family_cabinet.badge.expiring_soon"),
                    color: .orange
                )
            }
        }
        if let qty = box.totalQuantity, qty <= 0 {
            return Resolved(
                kind: .lowStock,
                text: L10n.text("home.medical.family_cabinet.badge.low_stock"),
                color: .orange
            )
        }
        return nil
    }
}
