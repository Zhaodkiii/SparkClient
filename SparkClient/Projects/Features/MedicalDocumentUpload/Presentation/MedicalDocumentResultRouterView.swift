import SwiftUI

/// 医疗文档分类识别结果路由页面：作为各类单据识别结果统一入口，通过视图分发跳转至对应类型的识别结果页面
struct MedicalDocumentResultRouterView: View {
    // 绑定上传业务视图模型，监听识别输出数据变化
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel

    /// 成员上下文存储实例，用于表单相关的家庭成员信息读取
    private var memberContextStore: MemberContextStore {
        viewModel.memberContextStoreForLocalForms
    }

    var body: some View {
        // 根据识别结果类型渲染对应页面
        destinationView
    }

    /// 视图分发构建器：根据识别输出的单据类型，匹配并展示对应结果页面
    @ViewBuilder
    private var destinationView: some View {
        // 存在识别输出结果时再进行页面分发
        if let output = viewModel.typedOutput {
            // 依据识别文档分类枚举，路由至对应结果视图
            switch output.typedResult {
            // 病历单识别结果页
            case .caseDocument:
                CaseRecognitionResultView(viewModel: viewModel)
            // 体检报告识别结果页
            case .healthExamReport:
                HealthExamRecognitionResultView(
                    viewModel: viewModel,
                    memberContextStore: memberContextStore
                )
            // 普通诊疗报告单识别结果页
            case .medicalReport:
                MedicalReportRecognitionResultView(viewModel: viewModel)
            // 处方单识别结果页
            case .prescription:
                PrescriptionRecognitionResultView(viewModel: viewModel)
            // 用药方案单识别结果页
            case .medicationPlan:
                MedicationRecognitionResultView(viewModel: viewModel)
            // 药盒/药品包装识别结果页
            case .medicineBoxes:
                MedicineBoxRecognitionResultView(viewModel: viewModel)
            }
        }
    }

}
