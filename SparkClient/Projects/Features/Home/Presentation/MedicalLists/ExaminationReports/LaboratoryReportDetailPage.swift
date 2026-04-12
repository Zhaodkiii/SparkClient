import SwiftUI

/// 实验室检查明细页：参考 `LabPanelView` 的表格式阅读体验。
struct LaboratoryReportDetailPage: View {
    let report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let resources: SparkMedicalWorkflowAPI
    var onDeleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingEditSheet = false
    @State private var isShowingDeleteAlert = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        (report.medExamDetails ?? []).sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id < rhs.id
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var mutationService: ExaminationReportServerMutationService {
        .init(resources: resources)
    }

    private var existingDraft: MedicalReportRecognitionDraft {
        MedicalReportRecognitionDraft(
            category: report.category,
            title: report.itemName ?? "",
            hospital: report.organizationName,
            doctor: report.doctorName,
            content: report.impression?.nonEmpty ?? report.findings?.nonEmpty ?? "",
            date: MedicalDateCoding.encodeISO8601(report.reportedAt ?? report.performedAt ?? Date()),
            details: detailItems.map {
                MedicalReportItem(
                    category: $0.category,
                    subCategory: $0.subCategory,
                    itemName: $0.itemName,
                    itemCode: $0.itemCode,
                    resultValue: $0.resultValue,
                    unit: $0.unit,
                    referenceRange: $0.referenceRange,
                    flag: $0.flag,
                    resultAt: $0.resultAt.map(MedicalDateCoding.encodeISO8601),
                    modality: $0.modality,
                    bodyPart: $0.bodyPart,
                    diagnosis: $0.diagnosis,
                    extra: $0.extra,
                    sortOrder: "\($0.sortOrder)"
                )
            }
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(spacing: 0) {
                LaboratoryDetailHeaderRow()
                    .background(.ultraThinMaterial)
                    .overlay(Divider(), alignment: .bottom)

                ForEach(detailItems, id: \.id) { item in
                    LaboratoryDetailRow(item: item)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(report.itemName?.nonEmpty ?? L10n.text("home.medical.list.examination_reports.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") {
                        isShowingEditSheet = true
                    }
                    Button("删除", role: .destructive) {
                        isShowingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            NavigationView {
                ExamReportFormView(
                    mode: .serverEdit(existing: existingDraft),
                    onServerSubmit: { draft in
                        try await mutationService.updateReport(report: report, draft: draft)
                    }
                )
            }
            .navigationViewStyle(.stack)
        }
        .alert("确认删除该检查报告？", isPresented: $isShowingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                guard isDeleting == false else { return }
                isDeleting = true
                Task {
                    do {
                        try await mutationService.deleteReport(reportID: report.id)
                        await MainActor.run {
                            onDeleted?()
                            dismiss()
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                        }
                    }
                    await MainActor.run {
                        isDeleting = false
                    }
                }
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if $0 == false { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct LaboratoryDetailHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            headerCell(L10n.text("home.medical.list.examination.detail.lab.item"), width: 180, alignment: .leading)
            headerCell(L10n.text("home.medical.list.examination.detail.lab.result"), width: 140)
            headerCell(L10n.text("home.medical.list.examination.detail.lab.reference"), width: 150)
            headerCell(L10n.text("home.medical.list.examination.detail.lab.status"), width: 120)
        }
        .padding(.vertical, 10)
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 12)
    }
}

private struct LaboratoryDetailRow: View {
    let item: SparkMedicalSyncAPI.RemoteMedExamDetail

    private var flagColor: Color {
        item.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : Color(uiColor: .systemGreen)
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(width: 180, alignment: .leading) {
                Text(item.itemName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            cell(width: 140) {
                HStack(spacing: 2) {
                    Text(item.resultValue ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if item.unit.isEmpty == false {
                        Text(item.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            cell(width: 150) {
                Text(item.referenceRange.nonEmpty ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            cell(width: 120) {
                Text(item.flag.nonEmpty ?? L10n.text("home.medical.list.examination.detail.lab.normal"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(flagColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(flagColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    private func cell<Content: View>(width: CGFloat, alignment: Alignment = .center, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 12)
    }
}
