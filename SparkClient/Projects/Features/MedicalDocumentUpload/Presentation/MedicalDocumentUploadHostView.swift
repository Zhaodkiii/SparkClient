import SwiftUI

/// 上传页面容器：只负责三态页面编排，业务逻辑交给 ViewModel。
///
/// **三态管理**：
/// - `.picking`: 显示 MedicalDocumentUploadPickingView，用户选择文件和类型
/// - `.processing`: 显示模式选择或识别进度
/// - `.result`: 显示 MedicalDocumentResultRouterView，展示识别结果
struct MedicalDocumentUploadHostView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch viewModel.stage {
            case .picking:
                MedicalDocumentUploadPickingView(viewModel: viewModel)
            case .processing:
                if viewModel.needsManualModeSelection {
                    MedicalDocumentUploadModeSelectionView { kind in
                        viewModel.selectedKind = kind
                        viewModel.needsManualModeSelection = false
                        viewModel.startRecognitionTask()
                    }
                } else if viewModel.progress != nil {
                    MedicalDocumentUploadProgressView(viewModel: viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .result:
                if viewModel.typedOutput != nil {
                    MedicalDocumentResultRouterView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle(L10n.text("medical.upload.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.dismissUploadPage()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .alert(L10n.text("common.error"), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button(L10n.text("medical.upload.error.confirm")) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#if DEBUG
#Preview {
    CompatibleNavigationContainer {
        MedicalDocumentUploadHostView(viewModel: .preview())
    }
}
#endif
