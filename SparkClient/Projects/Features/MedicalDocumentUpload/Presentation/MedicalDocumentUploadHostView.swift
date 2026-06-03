import SwiftUI

/// 上传页面容器：只负责三态页面编排，业务逻辑交给 ViewModel。
///
/// **三态管理**：
/// - `.picking`: 显示 MedicalDocumentUploadPickingView，用户选择文件和类型
/// - `.processing`: 显示模式选择或识别进度
/// - `.result`: 显示 MedicalDocumentResultRouterView，展示识别结果
struct MedicalDocumentUploadHostView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKeysSettingsSheet = false

    private var showMissingModelAlert: Binding<Bool> {
        Binding(
            get: { viewModel.missingModelScenarioForAlert != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.missingModelScenarioForAlert = nil
                }
            }
        )
    }

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
        .alert(L10n.text("medical.upload.missing_model.title"), isPresented: showMissingModelAlert) {
            Button(L10n.text("medical.upload.missing_model.action")) {
                showAPIKeysSettingsSheet = true
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("medical.upload.missing_model.message"))
        }
        .sheet(isPresented: $showAPIKeysSettingsSheet) {
            NavigationView {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                showAPIKeysSettingsSheet = false
                            }
                        }
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
        MedicalDocumentUploadHostView(
            viewModel: .preview(),
            aiSettingsViewModel: AppContainer.preview.makeAISettingsViewModel(ownerAccountID: 1)
        )
    }
}
#endif
