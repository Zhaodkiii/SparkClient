import Combine
import SwiftUI

/// 线上问诊第一步：科室选择（参考原系统"全部科室 / 最近问诊"双 Tab）。
struct ConsultDepartmentSelectView: View {
    @StateObject private var viewModel: ConsultDepartmentSelectViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    @ObservedObject private var routeStore: AppRouteStore

    private let dependencies: HospitalCareFeatureDependencies
    private let hospital: HospitalSummary
    private let sessionStore: AppSessionStore
    private let onOpenThread: (UUID) -> Void
    private let onOpenDetail: (HospitalConsultationDTO) -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        hospital: HospitalSummary,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        routeStore: AppRouteStore,
        initialTab: ConsultDepartmentSelectViewModel.Tab = .departments,
        onOpenThread: @escaping (UUID) -> Void,
        onOpenDetail: @escaping (HospitalConsultationDTO) -> Void
    ) {
        self.dependencies = dependencies
        self.hospital = hospital
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.routeStore = routeStore
        self.onOpenThread = onOpenThread
        self.onOpenDetail = onOpenDetail
        _viewModel = StateObject(
            wrappedValue: ConsultDepartmentSelectViewModel(
                dependencies: dependencies,
                hospital: hospital,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore,
                initialTab: initialTab
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("问诊入口", selection: $viewModel.selectedTab) {
                Text("全部科室").tag(ConsultDepartmentSelectViewModel.Tab.departments)
                Text("最近问诊").tag(ConsultDepartmentSelectViewModel.Tab.recent)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch viewModel.selectedTab {
            case .departments:
                departmentContent
            case .recent:
                RecentConsultationListView(
                    dependencies: dependencies,
                    memberContextStore: memberContextStore,
                    onOpenThread: onOpenThread,
                    onOpenDetail: onOpenDetail
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await viewModel.onAppear() }
        .onChange(of: memberContextStore.context.selectedMemberID) { _ in
            Task { await viewModel.reload() }
        }
    }

    private var departmentContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索科室、医生", text: $viewModel.keyword)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if viewModel.isLoading && viewModel.filteredDepartments.isEmpty {
                ProgressView("正在加载科室…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredDepartments.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text(viewModel.keyword.isEmpty ? "暂无可选科室" : "未找到匹配科室")
                        .foregroundStyle(.secondary)
                    if let error = viewModel.loadError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重试") { Task { await viewModel.reload() } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.filteredDepartments) { department in
                    Button {
                        routeStore.route(to: .hospitalDoctorSelect(
                            hospitalID: hospital.id,
                            departmentID: department.id
                        ))
                    } label: {
                        HStack {
                            Text(department.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

@MainActor
final class ConsultDepartmentSelectViewModel: ObservableObject {
    enum Tab: Hashable {
        case departments
        case recent
    }

    @Published var selectedTab: Tab = .departments
    @Published var keyword = ""
    @Published private(set) var departments: [HospitalDepartmentSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let dependencies: HospitalCareFeatureDependencies
    private let hospital: HospitalSummary
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private var hasLoadedOnce = false

    init(
        dependencies: HospitalCareFeatureDependencies,
        hospital: HospitalSummary,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        initialTab: Tab = .departments
    ) {
        self.dependencies = dependencies
        self.hospital = hospital
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.selectedTab = initialTab
    }

    var filteredDepartments: [HospitalDepartmentSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return departments }
        return departments.filter { $0.name.contains(trimmed) }
    }

    func onAppear() async {
        guard hasLoadedOnce == false else { return }
        hasLoadedOnce = true
        await reload()
    }

    func reload() async {
        guard case .signedIn(let session) = sessionStore.state else {
            loadError = "请先登录"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            departments = try await dependencies.loadDirectory.loadDepartments(
                accountID: session.accountID,
                hospitalID: hospital.id
            )
        } catch {
            loadError = "科室加载失败，请稍后重试"
        }
    }
}
