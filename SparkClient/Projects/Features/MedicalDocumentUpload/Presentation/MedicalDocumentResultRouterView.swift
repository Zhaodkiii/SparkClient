import SwiftUI

/// 分类型结果页路由：作为抽取结果入口，使用 NavigationLink 跳转到对应的结果页面模块。
struct MedicalDocumentResultRouterView: View {
    @EnvironmentObject private var memberContextStore: MemberContextStore
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel

    var body: some View {
        destinationView
    }

    @ViewBuilder
    private var destinationView: some View {
        if let output = viewModel.typedOutput {
            switch output.typedResult {
            case .caseDocument:
                CaseRecognitionResultView(viewModel: viewModel)
            case .healthExamReport:
                HealthExamRecognitionResultView(
                    viewModel: viewModel,
                    memberContextStore: memberContextStore
                )
            case .medicalReport:
                MedicalReportRecognitionResultView(viewModel: viewModel)
            case .prescription:
                PrescriptionRecognitionResultView(viewModel: viewModel)
            case .medicationPlan:
                MedicationRecognitionResultView(viewModel: viewModel)
            case .medicineBoxes:
                MedicineBoxRecognitionResultView(viewModel: viewModel)
            }
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
        guard let output = viewModel.typedOutput else { return "" }
        switch output.typedResult {
        case .caseDocument:
            return "病例"
        case .healthExamReport:
            return "体检"
        case .medicalReport:
            return "医疗报告"
        case .prescription:
            return "处方"
        case .medicationPlan:
            return "用药"
        case .medicineBoxes:
            return "药箱"
        }
    }
}
