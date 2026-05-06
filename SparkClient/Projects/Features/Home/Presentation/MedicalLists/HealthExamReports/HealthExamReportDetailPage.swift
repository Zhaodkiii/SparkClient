import SwiftUI

/// 体检报告详情页：独立模块，展示综述、异常项、明细与附件。
struct HealthExamReportDetailPage: View {
    let item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments
    let fileTransferService: FileTransferService

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        item.medExamDetails ?? []
    }

    private var abnormalItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        detailItems.filter { $0.flag.isPotentiallyAbnormal }
    }

    var body: some View {
        List {
            Section(L10n.text("home.medical.list.details.section")) {
                if let institutionName = item.institutionName?.nonEmpty {
                    metaRow("机构", institutionName)
                }
                if let reportNo = item.reportNo?.nonEmpty {
                    metaRow(L10n.text("home.medical.list.health_exam.stats.report_no"), reportNo)
                }
                if let examDate = item.examDate {
                    metaRow("日期", examDate.formatted(date: .abbreviated, time: .omitted))
                }
                metaRow(L10n.text("home.medical.list.health_exam.stats.items"), "\(detailItems.count)")
                metaRow(L10n.text("home.medical.list.health_exam.stats.abnormal"), "\(abnormalItems.count)")
            }

            if let summary = item.summary?.nonEmpty {
                Section("综述") {
                    Text(summary)
                        .font(.body)
                }
            }

            if abnormalItems.isEmpty == false {
                Section(L10n.text("home.medical.list.health_exam.high_risk.title")) {
                    ForEach(abnormalItems, id: \.id) { detail in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.itemName)
                                .font(.subheadline.weight(.semibold))
                            Text([detail.resultValue ?? "", detail.unit].filter { $0.isEmpty == false }.joined())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if detailItems.isEmpty == false {
                Section(L10n.text("home.medical.list.details.section")) {
                    ForEach(detailItems, id: \.id) { detail in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(detail.itemName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if detail.flag.isEmpty == false {
                                    Text(detail.flag)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(detail.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : .secondary)
                                }
                            }
                            Text([detail.resultValue ?? "", detail.unit].filter { $0.isEmpty == false }.joined())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let diagnosis = detail.diagnosis?.nonEmpty {
                                Text(diagnosis)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let attachments = item.attachments, attachments.isEmpty == false {
                Section(L10n.text("common.attachments")) {
                    MedicalAttachmentListView(
                        attachments: attachments,
                        fileTransferService: fileTransferService
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.institutionName?.nonEmpty ?? L10n.text("home.medical.list.health_exam_reports.title"))
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
