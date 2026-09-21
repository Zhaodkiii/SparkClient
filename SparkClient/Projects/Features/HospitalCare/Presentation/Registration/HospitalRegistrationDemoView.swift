import Combine
import SwiftUI

/// 挂号演示入口：只读取医院和科室目录，不创建真实预约单。
struct HospitalRegistrationDemoView: View {
    @StateObject private var viewModel: HospitalRegistrationDemoViewModel
    private let onFinish: () -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        onFinish: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: HospitalRegistrationDemoViewModel(dependencies: dependencies, memberContextStore: memberContextStore, sessionStore: sessionStore))
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            if viewModel.isLoadingEntry {
                ProgressView("正在加载医院科室…")
            } else if let error = viewModel.entryError {
                ContentUnavailableView("挂号服务暂不可用", systemImage: "cross.case", description: Text(error))
            } else {
                List(viewModel.filteredDepartments) { department in
                    NavigationLink {
                        HospitalRegistrationServiceView(
                            department: department,
                            viewModel: viewModel,
                            onFinish: onFinish
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cross.case.fill").foregroundStyle(Color.accentColor).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(department.name).foregroundStyle(.primary)
                                Text("选择普通号或专家号").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $viewModel.keyword, prompt: "搜索科室")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("预约挂号")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEntry() }
    }
}

struct RegistrationSelection {
    enum RegistrationType: Equatable { case general, expert; var title: String { self == .general ? "普通号" : "专家号" } }
    let department: HospitalDepartmentSummary
    var type: RegistrationType = .general
    var doctor: HospitalAgentCard?
    var date = Date()
    var slot: RegistrationSlot?
    var fee: Double { type == .general ? 12 : 22 }
    var displayTitle: String { type == .expert ? "\(doctor?.doctorDisplayName ?? "专家") · 专家号" : "\(department.name) · 普通号" }
}

struct RegistrationSlot: Identifiable, Equatable {
    let time: String
    let period: String
    let remaining: Int
    let total: Int
    var id: String { time }
}

struct RegistrationDay: Identifiable {
    let date: Date
    let weekday: String
    let day: String
    var id: Date { date }
}

@MainActor
final class HospitalRegistrationDemoViewModel: ObservableObject {
    @Published var hospital: HospitalSummary?
    @Published var departments: [HospitalDepartmentSummary] = []
    @Published var doctors: [HospitalAgentCard] = []
    @Published var keyword = ""
    @Published var isLoadingEntry = true
    @Published var isLoadingDoctors = false
    @Published var entryError: String?
    @Published var selectedDate = Date()

    let memberContextStore: MemberContextStore
    let days: [RegistrationDay]
    private let dependencies: HospitalCareFeatureDependencies
    private let sessionStore: AppSessionStore

    init(dependencies: HospitalCareFeatureDependencies, memberContextStore: MemberContextStore, sessionStore: AppSessionStore) {
        self.dependencies = dependencies
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        days = (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return nil }
            return RegistrationDay(date: date, weekday: date.formatted(.dateTime.weekday(.abbreviated)), day: date.formatted(.dateTime.month().day()))
        }
    }

    var filteredDepartments: [HospitalDepartmentSummary] { keyword.isEmpty ? departments : departments.filter { $0.name.localizedCaseInsensitiveContains(keyword) } }

    func loadEntry() async {
        guard isLoadingEntry else { return }
        guard case .signedIn(let session) = sessionStore.state else { isLoadingEntry = false; entryError = "请先登录"; return }
        defer { isLoadingEntry = false }
        let selectedID = await dependencies.selectionStore.selectedHospitalID(accountID: session.accountID)
        if let selectedID,
           let selected = try? await dependencies.remoteAPI.listHospitals(page: 1, pageSize: 100).first(where: { $0.id == selectedID }) {
            let summary = HospitalSummary(
                id: selected.id,
                code: selected.code ?? "",
                name: selected.name,
                shortName: selected.shortName ?? selected.name,
                introduction: selected.introduction ?? "",
                status: selected.status
            )
            self.hospital = summary
            do {
                departments = try await dependencies.loadDirectory.loadDepartments(accountID: session.accountID, hospitalID: summary.id)
            } catch {
                entryError = "科室加载失败，请稍后重试"
            }
            return
        }
        switch await dependencies.resolveDemoHospital.execute(accountID: session.accountID) {
        case .resolved(let hospital):
            self.hospital = hospital
            do { departments = try await dependencies.loadDirectory.loadDepartments(accountID: session.accountID, hospitalID: hospital.id) }
            catch { entryError = "科室加载失败，请稍后重试" }
        case .missing, .failed: entryError = "未找到可用医院数据"
        }
    }

    func loadDoctors(for department: HospitalDepartmentSummary) async {
        guard let hospital, case .signedIn(let session) = sessionStore.state else { return }
        isLoadingDoctors = true
        defer { isLoadingDoctors = false }
        doctors = (try? await dependencies.loadDirectory.loadAgents(accountID: session.accountID, hospitalID: hospital.id, departmentID: department.id, keyword: "", memberID: memberContextStore.context.selectedMemberID)) ?? []
    }

    func slots(for type: RegistrationSelection.RegistrationType) -> [RegistrationSlot] {
        let times = type == .expert ? ["09:00–09:30", "10:00–10:30", "14:00–14:30", "15:00–15:30"] : ["08:30–09:00", "09:30–10:00", "10:30–11:00", "13:00–13:30", "14:00–14:30", "15:00–15:30"]
        return times.enumerated().map { index, time in RegistrationSlot(time: time, period: index < 3 ? "上午" : "下午", remaining: max(2, 16 - index * 2), total: type == .expert ? 6 : 20) }
    }
}
