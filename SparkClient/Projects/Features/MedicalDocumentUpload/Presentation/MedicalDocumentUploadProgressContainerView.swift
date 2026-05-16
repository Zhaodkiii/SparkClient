import SwiftUI

/// 进度容器视图
/// 根据状态条件渲染不同的子视图：
/// - needsManualModeSelection == true → 显示类型选择视图
/// - progress != nil → 显示进度视图
/// - 否则 → 显示加载中
/// 负责管理 MedicalDocumentUploadProgressViewModel 的生命周期
struct MedicalDocumentUploadProgressContainerView: View {
    @Binding var progress: MedicalDocumentUploadProgress?
    @Binding var needsManualModeSelection: Bool
    let ocrText: String?
    let extractModelOptions: [MedicalDocumentUploadViewModel.RecognitionModelOption]
    @Binding var overrideDocumentKindForRetry: MedicalDocumentKind?
    @Binding var preferredExtractModelName: String?
    var onCancel: (() -> Void)? = nil
    var onRestart: (() -> Void)? = nil
    var onRetryFromFailedStep: (() -> Void)? = nil
    var onReturnToPicker: (() -> Void)? = nil
    var onSelectMode: ((MedicalDocumentKind) -> Void)? = nil
    
    @StateObject private var viewModel: MedicalDocumentUploadProgressViewModel
    
    init(
        progress: Binding<MedicalDocumentUploadProgress?>,
        needsManualModeSelection: Binding<Bool>,
        ocrText: String?,
        extractModelOptions: [MedicalDocumentUploadViewModel.RecognitionModelOption],
        overrideDocumentKindForRetry: Binding<MedicalDocumentKind?>,
        preferredExtractModelName: Binding<String?>,
        onCancel: (() -> Void)? = nil,
        onRestart: (() -> Void)? = nil,
        onRetryFromFailedStep: (() -> Void)? = nil,
        onReturnToPicker: (() -> Void)? = nil,
        onSelectMode: ((MedicalDocumentKind) -> Void)? = nil
    ) {
        self._progress = progress
        self._needsManualModeSelection = needsManualModeSelection
        self.ocrText = ocrText
        self.extractModelOptions = extractModelOptions
        self._overrideDocumentKindForRetry = overrideDocumentKindForRetry
        self._preferredExtractModelName = preferredExtractModelName
        self.onCancel = onCancel
        self.onRestart = onRestart
        self.onRetryFromFailedStep = onRetryFromFailedStep
        self.onReturnToPicker = onReturnToPicker
        self.onSelectMode = onSelectMode
        
        // 初始化 ViewModel（如果 progress 为 nil，使用默认值）
        let initialProgress = progress.wrappedValue ?? MedicalDocumentUploadProgress(
            title: L10n.text("medical.upload.processing.default_title"),
            statusLabel: L10n.text("medical.upload.status.processing"),
            elapsedSeconds: 0,
            estimatedSeconds: 60,
            steps: []
        )
        _viewModel = StateObject(wrappedValue: MedicalDocumentUploadProgressViewModel(progress: initialProgress))
    }
    
    var body: some View {
        Group {
            if needsManualModeSelection {
                // 需要手动选择类型
                MedicalDocumentUploadModeSelectionView(onSelectMode: onSelectMode)
            } else if progress != nil {
                // 显示进度视图
                MedicalDocumentUploadProgressView(
                    viewModel: viewModel,
                    ocrText: ocrText,
                    extractModelOptions: extractModelOptions,
                    overrideDocumentKindForRetry: $overrideDocumentKindForRetry,
                    preferredExtractModelName: $preferredExtractModelName,
                    onCancel: onCancel,
                    onRestart: onRestart,
                    onRetryFromFailedStep: onRetryFromFailedStep,
                    onReturnToPicker: onReturnToPicker
                )
            } else {
                // 加载中
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: progress) { newValue in
            handleProgressChange(newValue)
        }
    }
    
    // MARK: - 进度变化处理
    
    /// 处理 progress 绑定的变化
    /// 当 progress 变为 nil 时：停止计时器，清空步骤
    /// 当 progress 有值时：合并 elapsedSeconds，避免跳变
    private func handleProgressChange(_ newValue: MedicalDocumentUploadProgress?) {
        if newValue == nil {
            // 退出识别流程时清零
            viewModel.stopTimer()
            var cleared = viewModel.progress
            cleared.elapsedSeconds = 0
            cleared.steps = []
            viewModel.progress = cleared
        } else if let newProgress = newValue {
            // 父级只更新步骤等字段；已耗时由本地计时器累加
            // 取 max 避免每换一个步骤就把「已耗时」打回 0
            var merged = newProgress
            merged.elapsedSeconds = max(viewModel.progress.elapsedSeconds, newProgress.elapsedSeconds)
            viewModel.progress = merged
            
            // 开始计时器
            viewModel.startTimer()
        }
    }
}
