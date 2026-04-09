import SwiftUI

/// 医疗文档上传进度视图
/// 展示识别流程的进度，包括标题、状态标签、已用/预估时间和步骤列表
/// 支持动态操作按钮（取消/返回/重试）根据整体状态自动切换
struct MedicalDocumentUploadProgressView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadProgressViewModel
    var onCancel: (() -> Void)? = nil
    var onRestart: (() -> Void)? = nil
    var onReturnToPicker: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ProgressCardView(viewModel: viewModel)
            
            Spacer()
            
            // 操作按钮 - 根据整体状态动态显示
            actionButtons
        }
        .padding(.horizontal, 20)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 操作按钮
    
    /// 根据 overallState 动态显示不同的操作按钮
    /// - running: 显示「取消」按钮
    /// - failed: 显示「返回选择」和「重新识别」按钮
    /// - done: 不显示按钮（自动跳转结果页）
    private var actionButtons: some View {
        HStack(spacing: 16) {
            switch viewModel.progress.overallState {
            case .running:
                Button {
                    onCancel?()
                } label: {
                    Text(L10n.text("medical.upload.action.cancel"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
            case .failed:
                // 失败时显示两个按钮
                Button {
                    onReturnToPicker?()
                } label: {
                    Text(L10n.text("medical.upload.action.return_to_picker"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    onRestart?()
                } label: {
                    Text(L10n.text("medical.upload.action.restart"))
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)
                
            case .done, .idle:
                // 完成或空闲时不显示按钮
                EmptyView()
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - 进度卡片

/// 进度卡片视图
/// 展示标题、状态标签、时间信息和步骤列表
/// 使用渐变边框和阴影增强视觉层次
private struct ProgressCardView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadProgressViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            stepsList
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(.systemBlue).opacity(0.6),
                            Color(.systemIndigo).opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .blendMode(.overlay)
        )
    }
    
    // MARK: - 卡片头部
    
    /// 展示图标、标题、状态标签和时间信息
    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(.systemIndigo))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.progress.title)
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        Text(viewModel.progress.statusLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule()
                                    .fill(Color(.systemIndigo).opacity(0.12))
                            )
                        
                        if let timeString = formattedTimeString {
                            Text(timeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
    
    /// 格式化时间字符串
    /// 格式："当前已用时 X 分 X 秒（预计约 X 分钟）"
    private var formattedTimeString: String? {
        let elapsed = viewModel.progress.elapsedSeconds
        let estimated = viewModel.progress.estimatedSeconds
        
        guard elapsed > 0 || (estimated != nil && estimated! > 0) else { return nil }
        
        let elapsedMin = elapsed / 60
        let elapsedSec = elapsed % 60
        
        let elapsedPart: String = {
            if elapsedMin == 0 {
                return String(format: L10n.text("medical.upload.time.elapsed.seconds"), elapsedSec)
            } else {
                return String(format: L10n.text("medical.upload.time.elapsed.minutes"), elapsedMin, elapsedSec)
            }
        }()
        
        guard let est = estimated, est > 0 else {
            return elapsedPart
        }
        
        if est < 60 {
            return String(format: L10n.text("medical.upload.time.estimated.seconds"), elapsedPart, est)
        }
        
        let estMin = Int(ceil(Double(est) / 60.0))
        return String(format: L10n.text("medical.upload.time.estimated.minutes"), elapsedPart, estMin)
    }
    
    // MARK: - 步骤列表
    
    /// 展示所有步骤，每个步骤包含状态图标、标题和副标题
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.progress.steps.indices, id: \.self) { idx in
                let step = viewModel.progress.steps[idx]
                StepRow(step: step)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: L10n.text("medical.upload.a11y.step"), idx + 1, step.title))
                    .accessibilityValue(step.state.rawValue)
            }
        }
    }
}

// MARK: - 步骤行

/// 单个步骤的展示视图
/// 包含状态图标、标题和可选的副标题
private struct StepRow: View {
    let step: MedicalDocumentUploadStep
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StateIcon(state: step.state)
                .frame(width: 28, height: 28)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.subheadline.weight(step.state == .running ? .semibold : .regular))
                    .foregroundStyle(step.state == .idle ? .secondary : .primary)
                
                if let subtitle = step.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - 状态图标

/// 步骤状态的图标视图
/// 四种状态对应不同的视觉表现：
/// - idle: 灰色空心圆圈
/// - running: 旋转的渐变进度环
/// - done: 蓝色背景白色对勾
/// - failed: 红色背景警告图标
private struct StateIcon: View {
    let state: MedicalDocumentUploadStepState
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            switch state {
            case .idle:
                Circle()
                    .stroke(Color(uiColor: .separator), lineWidth: 2)
                    .frame(width: 28, height: 28)
                
            case .running:
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color(.systemBlue),
                                Color(.systemIndigo)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                    .onAppear { isAnimating = true }
                    .frame(width: 28, height: 28)
                
            case .done:
                Circle()
                    .fill(Color(.systemIndigo).opacity(0.12))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(.systemIndigo))
                    )
                
            case .failed:
                Circle()
                    .fill(Color(.systemRed).opacity(0.12))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.systemRed))
                    )
            }
        }
        .animation(.easeInOut, value: state)
    }
}
