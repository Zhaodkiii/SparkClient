import SwiftUI

/// 处方详情页：独立模块，展示批次基础信息、诊断、药品列表与附件。
struct PrescriptionBatchDetailPage: View {
    let item: SparkMedicalSyncAPI.RemotePrescriptionBatchComplete
    let fileTransferService: FileTransferService

    private var medications: [SparkMedicalSyncAPI.RemoteMedication] {
        item.medications ?? []
    }

    var body: some View {
        List {
            Section("处方信息") {
                if let institutionName = item.institutionName?.nonEmpty {
                    metaRow("机构", institutionName)
                }
                if let prescriberName = item.prescriberName?.nonEmpty {
                    metaRow("开方医生", prescriberName)
                }
                if let batchNo = item.batchNo?.nonEmpty {
                    metaRow("处方号", batchNo)
                }
                if let prescribedAt = item.prescribedAt {
                    metaRow("开方日期", prescribedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            if let diagnosis = item.diagnosis?.nonEmpty {
                Section(L10n.text("home.medical.list.medications.diagnosis")) {
                    Text(diagnosis)
                        .font(.body)
                }
            }

            if medications.isEmpty == false {
                Section(String(format: L10n.text("home.medical.list.medications.in_batch_count"), medications.count)) {
                    ForEach(medications, id: \.id) { medication in
                        NavigationLink {
                            MedicationDetailPage(item: medication)
                                .hidesMainTabBarWhenPushed()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(medication.drugName.nonEmpty ?? medication.genericName.nonEmpty ?? "")
                                    .font(.subheadline.weight(.semibold))
                                Text([medication.dosePerTime, medication.frequencyText].filter { $0.isEmpty == false }.joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let attachments = item.attachments, attachments.isEmpty == false {
                Section(L10n.text("home.medical.attachments.title")) {
                    MedicalAttachmentListView(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.institutionName?.nonEmpty ?? L10n.text("home.medical.list.medications.section.prescriptions"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}
