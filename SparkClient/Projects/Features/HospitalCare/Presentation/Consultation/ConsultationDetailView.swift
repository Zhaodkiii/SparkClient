import SwiftUI

/// 问诊详情（只读）：问诊编号、状态、医生与科室、主诉、开单项目、补充病史、附件数；
/// 底部"进入对话"直达关联问诊会话。
struct ConsultationDetailView: View {
    let consultation: HospitalConsultationDTO
    let onOpenThread: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                infoSection(title: "病情描述", text: consultation.chiefComplaint)
                if let items = consultation.orderItems, items.isEmpty == false {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionTitle("开单项目")
                        Text(items.joined(separator: "、"))
                            .font(.subheadline)
                    }
                }
                if let past = consultation.pastHistory, past.isEmpty == false {
                    infoSection(title: "既往史", text: past)
                }
                if let family = consultation.familyHistory, family.isEmpty == false {
                    infoSection(title: "家族史", text: family)
                }
                if let allergy = consultation.allergyHistory, allergy.isEmpty == false {
                    infoSection(title: "过敏史", text: allergy)
                }
                if let attachments = consultation.attachmentCount, attachments > 0 {
                    HStack(spacing: 6) {
                        sectionTitle("病历资料")
                        Label("\(attachments) 个附件", systemImage: "paperclip")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("会话内可查看")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                onOpenThread(consultation.threadId)
            } label: {
                Label("进入对话，与医生沟通", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemTeal))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(.bar)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(consultation.doctor?.displayName ?? consultation.agent.name ?? "问诊医生")
                    .font(.headline)
                if let title = consultation.doctor?.title, title.isEmpty == false {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ConsultationStatusText.label(for: consultation.serviceStatus))
                    .font(.caption)
                    .foregroundStyle(ConsultationStatusText.color(for: consultation.serviceStatus))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ConsultationStatusText.color(for: consultation.serviceStatus).opacity(0.12))
                    .clipShape(Capsule())
            }
            Text([consultation.department?.name, consultation.hospital?.shortName ?? consultation.hospital?.name]
                .compactMap { $0 }
                .filter { $0.isEmpty == false }
                .joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("问诊编号：\(consultation.consultNo)")
                Spacer()
                if let submittedAt = consultation.submittedAt {
                    Text(submittedAt, format: .dateTime.year().month().day().hour().minute())
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func infoSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
