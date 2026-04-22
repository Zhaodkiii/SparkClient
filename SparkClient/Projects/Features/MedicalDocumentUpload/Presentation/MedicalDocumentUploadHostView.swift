import SwiftUI

/// 上传页面容器：只负责三态页面编排，业务逻辑交给 ViewModel。
///
/// **三态管理**：
/// - `.picking`: 显示 MedicalDocumentUploadPickingView，用户选择文件和类型
/// - `.processing`: 显示 MedicalDocumentUploadProgressContainerView，展示识别进度
/// - `.result`: 显示 MedicalDocumentResultRouterView，展示识别结果
///
/// **进度阶段回调**：
/// - `onCancel`: 取消当前识别流程
/// - `onRestart`: 重新识别（保留已选文件）
/// - `onReturnToPicker`: 返回文件选择界面
/// - `onSelectMode`: 手动选择文档类型（当自动识别失败时）
struct MedicalDocumentUploadHostView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch viewModel.stage {
            case .picking:
                MedicalDocumentUploadPickingView(viewModel: viewModel)
            case .processing:
                // 使用新的进度容器视图，支持类型选择和进度展示
                MedicalDocumentUploadProgressContainerView(
                    progress: $viewModel.progress,
                    needsManualModeSelection: $viewModel.needsManualModeSelection,
                    onCancel: {
                        // 取消识别流程，重置到选择状态但保留文件
                        viewModel.resetRecognitionState()
                        viewModel.stage = .picking
                    },
                    onRestart: {
                        // 重新识别，保留已选文件
                        viewModel.resetRecognitionState()
                        Task {
                            await viewModel.startRecognition()
                        }
                    },
                    onReturnToPicker: {
                        // 返回文件选择界面
                        viewModel.resetRecognitionState()
                        viewModel.stage = .picking
                    },
                    onSelectMode: { kind in
                        // 用户手动选择了文档类型
                        viewModel.selectedKind = kind
                        viewModel.needsManualModeSelection = false
                        // 继续识别流程
                        Task {
                            await viewModel.startRecognition()
                        }
                    }
                )
            case .result:
                if let output = viewModel.typedOutput {
                    MedicalDocumentResultRouterView(
                        output: output,
                        isSaving: viewModel.isSaving,
                        saveReceipt: viewModel.saveReceipt,
                        onBack: { viewModel.reset() },
                        onSave: {
                            Task {
                                _ = await viewModel.saveResult()
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle(L10n.text("medical.upload.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .alert(L10n.text("medical.upload.error.title"), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button(L10n.text("medical.upload.error.confirm")) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    CompatibleNavigationContainer {
        MedicalDocumentUploadHostView(viewModel: .preview())
    }
}
