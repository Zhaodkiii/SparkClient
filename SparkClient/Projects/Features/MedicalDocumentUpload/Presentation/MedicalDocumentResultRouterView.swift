import SwiftUI

/// 分类型结果页路由：作为抽取结果入口，使用 NavigationLink 跳转到对应的结果页面模块。
struct MedicalDocumentResultRouterView: View {
    @EnvironmentObject private var memberContextStore: MemberContextStore

    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSelectMember: (Int?) -> Void
    let onSave: () -> Void

    var body: some View {
        destinationView
//        ScrollView {
//            VStack(alignment: .leading, spacing: 16) {
//                headerCard
//
//                NavigationLink {
//                    destinationView
//                } label: {
//                    routeCard
//                }
//                .buttonStyle(.plain)
//
//                Button("返回上传") {
//                    onBack()
//                }
//                .buttonStyle(.bordered)
//            }
//            .padding(16)
//        }
//        .background(Color(uiColor: .systemGroupedBackground))
//        .navigationTitle("抽取结果")
//        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch output.typedResult {
        case .caseDocument:
            CaseRecognitionResultView(
                output: output,
                isSaving: isSaving,
                saveReceipt: saveReceipt,
                onBack: onBack,
                onSave: onSave
            )
        case .healthExamReport:
            HealthExamRecognitionResultView(
                output: output,
                memberContextStore: memberContextStore,
                isSaving: isSaving,
                saveReceipt: saveReceipt,
                onBack: onBack,
                onSelectMember: onSelectMember,
                onSave: onSave
            )
        case .medicalReport:
            MedicalReportRecognitionResultView(
                output: output,
                isSaving: isSaving,
                saveReceipt: saveReceipt,
                onBack: onBack,
                onSave: onSave
            )
        case .prescription:
            PrescriptionRecognitionResultView(
                output: output,
                isSaving: isSaving,
                saveReceipt: saveReceipt,
                onBack: onBack,
                onSave: onSave
            )
        case .medication:
            MedicationRecognitionResultView(
                output: output,
                isSaving: isSaving,
                saveReceipt: saveReceipt,
                onBack: onBack,
                onSave: onSave
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("识别完成")
                .font(.headline)
            Text("已识别为\(routeLabel)，点击下方进入对应结果页面。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    private var routeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(routeLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("进入\(routeLabel)识别结果")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    private var routeLabel: String {
        switch output.typedResult {
        case .caseDocument:
            return "病例"
        case .healthExamReport:
            return "体检"
        case .medicalReport:
            return "医疗报告"
        case .prescription:
            return "处方"
        case .medication:
            return "用药"
        }
    }
}
