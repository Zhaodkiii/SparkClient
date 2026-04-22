import Foundation

@MainActor
protocol TaskRuntimeSyncing: AnyObject {
    func configure(taskService: TaskService, logger: Logger)
    func syncIncremental(memberID: Int?) async
}

extension TaskManager: TaskRuntimeSyncing {}
