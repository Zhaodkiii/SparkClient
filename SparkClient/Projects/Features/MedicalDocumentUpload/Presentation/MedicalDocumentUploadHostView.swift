import SwiftUI

/// 病历上传根容器页面
/// 仅负责三阶段页面切换布局，所有上传、识别业务逻辑交由 ViewModel 处理
///
/// 三阶段状态说明：
/// 1. .picking 文件选择页：相册/相机选择病历、选择文档类型
/// 2. .processing 处理中：手动选择识别模式 / AI识别进度加载页
/// 3. .result 识别结果页：路由到对应病历结果表单
struct MedicalDocumentUploadHostView: View {
    /// 上传业务视图模型，管理全流程状态、文件、识别任务、错误信息
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    /// AI配置视图模型，用于跳转API密钥设置页面
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    /// 系统环境变量：关闭当前全屏弹窗
    @Environment(\.dismiss) private var dismiss

    /// 本地弹窗状态：缺少AI模型时跳转密钥设置页面
    @State private var showAPIKeysSettingsSheet = false

    /// 缺少AI模型弹窗绑定，同步ViewModel内缺失模型场景标识
    private var showMissingModelAlert: Binding<Bool> {
        Binding(
            get: { viewModel.missingModelScenarioForAlert != nil },
            set: { isPresented in
                // 关闭弹窗时清空场景标记
                if isPresented == false {
                    viewModel.missingModelScenarioForAlert = nil
                }
            }
        )
    }

    var body: some View {
        Group {
            // 根据当前阶段渲染对应子页面
            switch viewModel.stage {
            case .picking:
                // 第一步：文件选择页面
                MedicalDocumentUploadPickingView(viewModel: viewModel)
            case .processing:
                // 第二步：识别处理阶段
                if viewModel.needsManualModeSelection {
                    // 需要用户手动选择病历识别类型
                    MedicalDocumentUploadModeSelectionView { kind in
                        viewModel.selectedKind = kind
                        viewModel.needsManualModeSelection = false
                        viewModel.startRecognitionTask()
                    }
                } else if viewModel.progress != nil {
                    // 展示AI识别实时进度条页面
                    MedicalDocumentUploadProgressView(viewModel: viewModel)
                } else {
                    // 默认加载占位动画
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .result:
                // 第三步：识别完成结果页面
                if viewModel.typedOutput != nil {
                    MedicalDocumentResultRouterView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle(L10n.text("medical.upload.title"))
        .navigationBarTitleDisplayMode(.inline)
        // 顶部导航栏
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 关闭上传页面按钮
                Button {
                    viewModel.dismissUploadPage()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        // 弹窗：缺失AI模型提示
        .alert(L10n.text("medical.upload.missing_model.title"), isPresented: showMissingModelAlert) {
            Button(L10n.text("medical.upload.missing_model.action")) {
                // 前往API密钥配置页面
                showAPIKeysSettingsSheet = true
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("medical.upload.missing_model.message"))
        }
        // API密钥设置弹窗
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
        // 全局错误弹窗：识别/上传失败提示
        .alert(L10n.text("common.error"), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button(L10n.text("medical.upload.error.confirm")) {
                // 确认后清空错误信息
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
