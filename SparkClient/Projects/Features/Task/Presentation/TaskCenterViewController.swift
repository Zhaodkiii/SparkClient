import SwiftUI

enum TaskCenterRoute: Hashable {
    case detail(taskID: Int)
    case statistics
}

struct TaskCenterViewController: View {
    let memberID: Int?
    let knowledgeDependencies: KnowledgeFeatureDependencies

    @ObservedObject var taskManager: TaskManager
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    @State private var filters = TaskFilterSelection()
    @State private var path: [TaskCenterRoute] = []
    @State private var isCreating = false
    @State private var isShowingAdvancedFilters = false

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
                            isShowingAdvancedFilters = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if filters.advancedActiveCount > 0 {
                                    Text("\(filters.advancedActiveCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Color.accentColor, in: Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .accessibilityLabel(NSLocalizedString("task.filter.advanced", comment: "筛选"))
                    }
                }
            }
        } destination: { route in
            switch route {
            case .detail(let taskID):
                TaskDetailView(
                    memberID: memberID,
                    taskManager: taskManager,
                    knowledgeDependencies: knowledgeDependencies,
                    knowledgeViewModel: knowledgeViewModel,
                    taskID: taskID
                )
            case .statistics:
                TaskStatisticsView(
                    memberID: memberID,
                    taskManager: taskManager
                )
            }
        }
        .sheet(isPresented: $isShowingAdvancedFilters) {
            TaskAdvancedFilterSheet(filters: $filters) {
                isShowingAdvancedFilters = false
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
