import SwiftUI

/// 影像检查明细页：聚合部位、模态、结果与诊断。
struct ImagingReportDetailPage: View {
    let report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments
    let resources: SparkMedicalResourceAPI
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
        List {
            ForEach(detailItems, id: \.id) { item in
                ImagingDetailCard(item: item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(report.itemName?.nonEmpty ?? L10n.text("home.medical.list.examination.category.imaging"))
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

private struct ImagingDetailCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedExamDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.itemName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if item.flag.isEmpty == false {
                    Text(item.flag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.flag.isPotentiallyAbnormal ? Color(uiColor: .systemRed) : .secondary)
                }
            }

            detailRow(L10n.text("home.medical.list.examination.card.category"), item.category)
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.modality"), item.modality.nonEmpty ?? "—")
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.body_part"), item.bodyPart.nonEmpty ?? "—")
            detailRow(L10n.text("home.medical.list.examination.detail.imaging.result"), [item.resultValue ?? "", item.unit].filter { $0.isEmpty == false }.joined())

            if let diagnosis = item.diagnosis?.nonEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("home.medical.list.examination.detail.imaging.diagnosis"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(diagnosis)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
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
