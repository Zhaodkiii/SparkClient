import SwiftUI

/// 病例详情页：独立模块，承接列表卡片的 `NavigationLink` 跳转。
struct MedicalCaseDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let fileTransferService: FileTransferService

    var body: some View {
        List {
            detailSection(
                title: L10n.text("home.medical.list.medical_case.chief_complaint"),
                value: item.title?.nonEmpty
            )
            detailSection(
                title: L10n.text("home.medical.list.medical_case.diagnosis"),
                value: item.diagnosisSummary?.nonEmpty
            )

            if let symptoms = item.symptoms, symptoms.isEmpty == false {
                Section(L10n.text("home.medical.list.medical_case.symptoms")) {
                    ForEach(symptoms, id: \.self) { symptom in
                        Text(symptom)
                            .font(.body)
                    }
                }
            }

            if let medications = item.medications, medications.isEmpty == false {
                Section(L10n.text("home.medical.list.medical_case.medications")) {
                    ForEach(medications, id: \.self) { medication in
                        Text(medication)
                            .font(.body)
                    }
                }
            }

            Section(L10n.text("home.medical.list.details.section")) {
                if let hospitalName = item.hospitalName?.nonEmpty {
                    metaRow("医院", hospitalName)
                }
                if let recordType = item.recordType?.nonEmpty {
                    metaRow("类型", recordType)
                }
                if let ageAtVisit = item.ageAtVisit {
                    metaRow("就诊年龄", "\(ageAtVisit)")
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
        .navigationTitle(item.title?.nonEmpty ?? L10n.text("home.medical.list.medical_cases.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func detailSection(title: String, value: String?) -> some View {
        if let value {
            Section(title) {
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
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
