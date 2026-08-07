import SwiftUI

enum TaskCenterRoute: Hashable {
    case detail(taskID: Int)
    case statistics
}

struct TaskCenterViewController: View {
    let memberID: Int?

    @ObservedObject var taskManager: TaskManager
    @State private var filters = TaskFilterSelection()
    @State private var path: [TaskCenterRoute] = []
    @State private var isCreating = false

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            TaskListView(
                memberID: memberID,
                taskManager: taskManager,
                filters: $filters,
                onSelectTask: { task in
                    path.append(.detail(taskID: task.id))
                },
                onCreate: {
                    isCreating = true
                }
            )
            .navigationTitle(NSLocalizedString("task.center.title", comment: "任务中心"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            path.append(.statistics)
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            isCreating = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isCreating = true
                } label: {
                    Label(NSLocalizedString("task.empty.create", comment: "新建任务"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        } destination: { route in
            switch route {
            case .detail(let taskID):
                TaskDetailView(
                    memberID: memberID,
                    taskManager: taskManager,
                    taskID: taskID
                )
            case .statistics:
                TaskStatisticsView(
                    memberID: memberID,
                    taskManager: taskManager
                )
            }
        }
        .task {
            await taskManager.loadInitial(memberID: memberID)
            await taskManager.syncIncremental(memberID: memberID)
        }
        .sheet(isPresented: $isCreating) {
            CompatibleNavigationContainer {
                TaskCreateView(
                    memberID: memberID,
                    taskManager: taskManager,
                    mode: .create,
                    onDismiss: { isCreating = false }
                )
            }
        }
    }
}
