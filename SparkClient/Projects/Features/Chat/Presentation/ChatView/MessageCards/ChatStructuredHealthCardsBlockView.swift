import SwiftUI

/// 对话内四类结构化医疗卡片容器（保存按钮 + 摘要展示），数据来自 `structured_health_cards` 附件。
struct ChatStructuredHealthCardsBlockView: View {
    let blob: StructuredHealthCardsBlob
    @ObservedObject var memberContextStore: MemberContextStore
    let isSavingIDs: Set<UUID>
    let onAction: (ChatStructuredHealthCardAction) -> Void

    private var members: [Member] {
        memberContextStore.context.members
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if blob.medications.isEmpty == false {
                sectionHeader("chat.medical_card.section.medications", systemImage: "pills.fill", tint: .green)
                ForEach(blob.medications) { card in
                    let item = ChatStructuredHealthCardItem.medication(card)
                    medicalRow(
                        title: card.displayName,
                        subtitle: [card.specification, card.dosageLine].compactMap { $0 }.joined(separator: "\n"),
                        item: item,
                        isSaving: isSavingIDs.contains(item.id),
                        onSetMember: { memberID in
                            onAction(.setMember(item, memberID))
                        },
                        action: { onAction(.save(item)) }
                    )
                }
            }
            if blob.prescriptions.isEmpty == false {
                sectionHeader("chat.medical_card.section.prescriptions", systemImage: "doc.text.fill", tint: .blue)
                ForEach(blob.prescriptions) { card in
                    let item = ChatStructuredHealthCardItem.prescription(card)
                    medicalRow(
                        title: card.title,
                        subtitle: card.subtitle,
                        item: item,
                        isSaving: isSavingIDs.contains(item.id),
                        onSetMember: { memberID in
                            onAction(.setMember(item, memberID))
                        },
                        action: { onAction(.save(item)) }
                    )
                }
            }
            if blob.examReports.isEmpty == false {
                sectionHeader("chat.medical_card.section.exam_reports", systemImage: "cross.case.fill", tint: .orange)
                ForEach(blob.examReports) { card in
                    let item = ChatStructuredHealthCardItem.examReport(card)
                    medicalRow(
                        title: card.title,
                        subtitle: [card.hospital, card.dateText].compactMap { $0 }.joined(separator: " · "),
                        item: item,
                        isSaving: isSavingIDs.contains(item.id),
                        onSetMember: { memberID in
                            onAction(.setMember(item, memberID))
                        },
                        action: { onAction(.save(item)) }
                    )
                }
            }
            if blob.medicalCases.isEmpty == false {
                sectionHeader("chat.medical_card.section.cases", systemImage: "heart.text.square.fill", tint: .purple)
                ForEach(blob.medicalCases) { card in
                    let item = ChatStructuredHealthCardItem.medicalCase(card)
                    medicalRow(
                        title: card.title,
                        subtitle: card.diagnosisLine,
                        item: item,
                        isSaving: isSavingIDs.contains(item.id),
                        onSetMember: { memberID in
                            onAction(.setMember(item, memberID))
                        },
                        action: { onAction(.save(item)) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ key: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(L10n.text(key))
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }

    private func medicalRow(
        title: String,
        subtitle: String?,
        item: ChatStructuredHealthCardItem,
        isSaving: Bool,
        onSetMember: @escaping (Int?) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                memberMenu(memberID: item.memberID, onSelect: onSetMember)
            }
            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if item.isSaved {
                    Label(L10n.text("chat.medical_card.saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button(action: action) {
                        HStack {
                            if isSaving {
                                ProgressView().scaleEffect(0.85)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text(L10n.text("chat.medical_card.save_to_health"))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func memberMenu(memberID: Int?, onSelect: @escaping (Int?) -> Void) -> some View {
        MemberProfileBindingMenu(
            memberContextStore: memberContextStore,
            selectedMemberID: memberID,
            onSelect: onSelect
        ) {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .imageScale(.small)
                Text(memberName(for: memberID))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(memberID == nil ? .secondary : Color(uiColor: .systemGreen))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
        }
    }

    private func memberName(for memberID: Int?) -> String {
        guard let memberID else {
            return L10n.text("medical.upload.member.not_selected")
        }
        return members.first(where: { $0.id == memberID })?.name
            ?? L10n.text("chat.composer.member_profile.unknown")
    }
}
