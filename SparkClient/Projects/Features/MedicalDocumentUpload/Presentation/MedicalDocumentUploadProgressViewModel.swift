import Combine
import SwiftUI

/// 进度视图 ViewModel
/// 负责管理 MedicalDocumentUploadProgress 的本地状态，包括计时器更新
/// 与父级 ViewModel 分离，独立管理本地状态如 elapsedSeconds
@MainActor
final class MedicalDocumentUploadProgressViewModel: ObservableObject {
    @Published var progress: MedicalDocumentUploadProgress
    private var timerCancellable: AnyCancellable?
    
    init(progress: MedicalDocumentUploadProgress) {
        self.progress = progress
    }
    
    // MARK: - 计时器管理
    
    /// 启动计时器，每秒更新 elapsedSeconds
    /// 用于在界面上显示已用时间
    func startTimer() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.progress.elapsedSeconds += 1
            }
    }
    
    /// 停止计时器
    /// 在视图消失或流程结束时调用
    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    // MARK: - 步骤状态管理
    
    /// 更新指定步骤的状态
    /// 如果步骤不存在，不执行任何操作
    /// - Parameters:
    ///   - stepId: 步骤 ID
    ///   - state: 新状态
    func updateStepState(stepId: String, state: MedicalDocumentUploadStepState) {
        guard let idx = progress.steps.firstIndex(where: { $0.id == stepId }) else { return }
        progress.steps[idx].state = state
    }
    
    /// 设置当前步骤为 running，并自动将之前的步骤标记为 done
    /// 用于流程推进时自动更新状态
    /// - Parameter stepId: 当前步骤 ID
    func setCurrentStep(stepId: String) {
        for (idx, step) in progress.steps.enumerated() {
            if step.id == stepId {
                // 将当前步骤设为 running
                progress.steps[idx].state = .running
                // 将之前的步骤标记为 done
                for prevIdx in 0..<idx {
                    if progress.steps[prevIdx].state != .done && progress.steps[prevIdx].state != .failed {
                        progress.steps[prevIdx].state = .done
                    }
                }
            } else if step.state == .running && step.id != stepId {
                // 将其他 running 的步骤设为 done
                progress.steps[idx].state = .done
            }
        }
    }
    
    /// 添加新步骤或更新已有步骤
    /// 如果步骤已存在，更新其状态；否则添加到列表末尾
    /// - Parameters:
    ///   - step: 步骤模型
    func addOrUpdateStep(_ step: MedicalDocumentUploadStep) {
        if let idx = progress.steps.firstIndex(where: { $0.id == step.id }) {
            // 更新已有步骤
            progress.steps[idx] = step
        } else {
            // 添加新步骤
            progress.steps.append(step)
        }
    }
    
    // MARK: - 批量操作
    
    /// 标记所有步骤为完成
    /// 通常在流程成功结束时调用
    func markAllStepsDone() {
        for idx in progress.steps.indices {
            if progress.steps[idx].state != .failed {
                progress.steps[idx].state = .done
            }
        }
        progress.statusLabel = L10n.text("medical.upload.status.completed")
    }
    
    /// 标记当前进行中的步骤为失败
    /// 用于捕获和处理流程错误
    func markCurrentStepFailed() {
        if let runningIdx = progress.steps.firstIndex(where: { $0.state == .running }) {
            progress.steps[runningIdx].state = .failed
        } else {
            // 如果没有运行中的步骤，将第一个未完成的步骤标记为失败
            if let firstIncompleteIdx = progress.steps.firstIndex(where: { $0.state != .done && $0.state != .failed }) {
                progress.steps[firstIncompleteIdx].state = .failed
            }
        }
        progress.statusLabel = L10n.text("medical.upload.status.failed")
    }
    
    // MARK: - 状态更新
    
    /// 更新进度标题
    /// - Parameter title: 新标题
    func updateTitle(_ title: String) {
        progress.title = title
    }
    
    /// 更新状态标签
    /// - Parameter statusLabel: 新状态标签
    func updateStatusLabel(_ statusLabel: String) {
        progress.statusLabel = statusLabel
    }
    
    /// 更新预估时间
    /// - Parameter estimatedSeconds: 预估秒数
    func updateEstimatedSeconds(_ estimatedSeconds: Int?) {
        progress.estimatedSeconds = estimatedSeconds
    }
}
