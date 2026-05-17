import SwiftUI
import UIKit

/// 医疗文档上传进度视图
/// 展示识别流程的进度，包括标题、状态标签、已用/预估时间和步骤列表
/// 支持动态操作按钮（取消/返回/重试）根据整体状态自动切换
struct MedicalDocumentUploadProgressView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    @State private var isShowingOCRText = false
    @State private var displayedOCRText: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ProgressCardView(
                viewModel: viewModel,
                onShowOCRText: {
                    isShowingOCRText = true
                }
            )

            Spacer()

            // 操作按钮 - 根据整体状态动态显示
            actionButtons
        }
        .padding(.horizontal, 20)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingOCRText) {
            CompatibleNavigationContainer {
                OCRTextUIKitView(text: displayedOCRText ?? "加载中...")
                    .navigationTitle("OCR 全文")
                    .navigationBarTitleDisplayMode(.inline)
                    .task {
                        await Task.yield()
                        displayedOCRText = ocrTextForDisplay
                    }
                    .onDisappear {
                        displayedOCRText = nil
                    }
            }
        }
    }

    private var ocrTextForDisplay: String {
        guard let text = viewModel.pipelineOCRText, !text.isEmpty else {
            return "暂无 OCR 内容"
        }
        return text
    }

    // MARK: - 操作按钮

    /// 根据整体阶段动态显示不同的操作按钮
    /// - running: 显示「取消」按钮
    /// - failed: 显示「返回选择」和「重新识别」按钮
    /// - done: 不显示按钮（自动跳转结果页）
    private var actionButtons: some View {
        HStack(spacing: 16) {
            switch viewModel.progress?.overallOutcome ?? .pending {
            case .running:
                Button {
                    viewModel.cancelRecognition()
                } label: {
                    Text(L10n.text("medical.upload.action.cancel"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .failed:
                // 失败时显示两个按钮
                Button {
                    viewModel.resetRecognitionState()
                    viewModel.stage = .picking
                } label: {
                    Text(L10n.text("medical.upload.action.return_to_picker"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.resetRecognitionState()
                    viewModel.startRecognitionTask()
                } label: {
                    Text("从头重来")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.resumeRecognitionTask()
                } label: {
                    Text("继续识别")
                        .font(.subheadline)
                }
                .buttonStyle(.borderedProminent)

            case .success, .skipped, .pending:
                // 完成或空闲时不显示按钮
                EmptyView()
            }
        }
        .padding(.bottom, 20)
    }
}

private struct OCRTextUIKitView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = UIColor.label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard uiView.text != text else { return }
        uiView.text = text
    }
}

// MARK: - 进度卡片

/// 进度卡片视图
/// 展示标题、状态标签、时间信息和步骤列表
/// 使用渐变边框和阴影增强视觉层次
private struct ProgressCardView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    var onShowOCRText: () -> Void

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
                    Text(viewModel.progress?.title ?? "")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(viewModel.progress?.statusLabel ?? "")
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
        let elapsed = viewModel.progress?.elapsedSeconds ?? 0
        let estimated = viewModel.progress?.estimatedSeconds

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

    /// 已开始或已结束的步骤（不含 `.pending`）
    private var visibleSteps: [MedicalDocumentUploadStep] {
        (viewModel.progress?.steps ?? []).filter { $0.flowStep.outcome != .pending }
    }

    /// 展示已开始/已结束的步骤，每个步骤包含状态图标、标题和副标题
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { idx, step in
                StepRow(
                    viewModel: viewModel,
                    step: step,
                    onShowOCRText: onShowOCRText
                )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: L10n.text("medical.upload.a11y.step"), idx + 1, step.flowStep.title()))
                    .accessibilityValue(step.flowStep.outcome.accessibilityValue)
            }
        }
    }
}

// MARK: - 步骤行

/// 单个步骤的展示视图
/// 包含状态图标、标题和可选的副标题
private struct StepRow: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    let step: MedicalDocumentUploadStep
    var onShowOCRText: () -> Void

    private var outcome: MedicalDocumentUploadFlowStep.CompletionOutcome { step.flowStep.outcome }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StateIcon(outcome: outcome)
                .frame(width: 28, height: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.flowStep.title())
                    .font(.subheadline.weight(outcome.isRunning ? .semibold : .regular))
                    .foregroundStyle(isPending ? .secondary : .primary)

                if let subtitle = step.flowStep.subtitle() {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .trailing, spacing: 6) {
                if step.elapsedMilliseconds > 0 {
                    Text("任务耗时：\(formattedElapsedDuration)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                stepOperations
            }
            if outcome.isFailed {
                Button("重试") {
                    viewModel.resumeRecognitionTask()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var stepOperations: some View {
        switch step.flowStep.kind {
        case .upload:
            if let resultSummary = step.resultSummary {
                Text(resultSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
        case .ocr where viewModel.pipelineOCRText?.isEmpty == false && outcome.isTerminalSuccess:
            
            if let resultSummary = step.resultSummary {
                Button(resultSummary) {
                    onShowOCRText()
                }
                .font(.caption.weight(.semibold))
            }
       
            // 类型识别失败 → 手动选择文档类型
        case .typeRecognition:
            Menu {
                ForEach(MedicalDocumentKind.allCases.filter { $0 != .auto }, id: \.self) { kind in
                    Button {
                        viewModel.selectOverrideDocumentKindForRetry(kind)
                    } label: {
                        Label(kind.localizedUploadLabel, systemImage: viewModel.overrideDocumentKindForRetry == kind ? "checkmark" : "doc.text")
                    }
                }
            } label: {
                Label(viewModel.overrideDocumentKindForRetry?.localizedUploadLabel ?? "改类型", systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
            }

            // 提取失败 → 切换模型
        case .extract where outcome.isFailed && !viewModel.extractModelOptions.isEmpty:
            Menu {
                Button {
                    viewModel.preferredExtractModelName = nil
                } label: {
                    Label("默认模型", systemImage: viewModel.preferredExtractModelName == nil ? "checkmark" : "cpu")
                }
                ForEach(viewModel.extractModelOptions) { option in
                    Button {
                        viewModel.preferredExtractModelName = option.name
                    } label: {
                        Label(option.displayName, systemImage: viewModel.preferredExtractModelName == option.name ? "checkmark" : "cpu")
                    }
                }
            } label: {
                Label(selectedModelLabel, systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
            }

            // 其他步骤失败 → 重试
        default:
            if outcome.isFailed {
                Button("重试") {
                    viewModel.resumeRecognitionTask()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var selectedModelLabel: String {
        // 从ViewModel获取用户选择的模型名称，并匹配到对应的模型选项
        guard let preferredExtractModelName = viewModel.preferredExtractModelName,
              let option = viewModel.extractModelOptions.first(where: { $0.name == preferredExtractModelName })
        else {
            return "改模型"
        }
        return option.displayName
    }

    private var formattedElapsedDuration: String {
        let ms = step.elapsedMilliseconds
        if ms < 1000 {
            return "\(ms)ms"
        }
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 {
            return "\(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }

    private var isPending: Bool {
        outcome == .pending
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
    let outcome: MedicalDocumentUploadFlowStep.CompletionOutcome
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            switch outcome {
            case .pending:
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

            case .success, .skipped:
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
        .animation(.easeInOut, value: outcome)
    }
}
