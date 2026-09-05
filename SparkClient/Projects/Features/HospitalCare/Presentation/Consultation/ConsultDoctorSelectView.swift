import Combine
import SwiftUI

/// 全局路由入口：只携带 hospitalID + departmentID，回源后再展示医生选择页。
struct ConsultDoctorSelectRouteView: View {
    @ObservedObject private var routeStore: AppRouteStore

    private let dependencies: HospitalCareFeatureDependencies
    private let hospitalID: UUID
    private let departmentID: UUID
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore

    @State private var hospital: HospitalSummary?
    @State private var department: HospitalDepartmentSummary?
    @State private var loadFailed = false

    init(
        dependencies: HospitalCareFeatureDependencies,
        hospitalID: UUID,
        departmentID: UUID,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        routeStore: AppRouteStore
    ) {
        self.dependencies = dependencies
        self.hospitalID = hospitalID
        self.departmentID = departmentID
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.routeStore = routeStore
    }

    var body: some View {
        Group {
            if let hospital, let department {
                ConsultDoctorSelectView(
                    dependencies: dependencies,
                    hospital: hospital,
                    department: department,
                    memberContextStore: memberContextStore,
                    sessionStore: sessionStore,
                    routeStore: routeStore
                )
            } else if loadFailed {
                VStack(spacing: 12) {
                    Spacer()
                    Text("医生列表暂不可用")
                        .font(.headline)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("正在加载医生…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("线上复诊")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard case .signedIn(let session) = sessionStore.state else {
            loadFailed = true
            return
        }
        loadFailed = false
        hospital = nil
        department = nil

        let resolvedHospital: HospitalSummary?
        if let cached = dependencies.catalogCache.hospitals(accountID: session.accountID)?
            .first(where: { $0.id == hospitalID }) {
            resolvedHospital = cached
        } else {
            _ = await dependencies.resolveDemoHospital.execute(accountID: session.accountID)
            resolvedHospital = dependencies.catalogCache.hospitals(accountID: session.accountID)?
                .first(where: { $0.id == hospitalID })
        }

        guard let resolvedHospital else {
            loadFailed = true
            return
        }

        do {
            let departments = try await dependencies.loadDirectory.loadDepartments(
                accountID: session.accountID,
                hospitalID: resolvedHospital.id
            )
            guard let matched = departments.first(where: { $0.id == departmentID }) else {
                loadFailed = true
                return
            }
            hospital = resolvedHospital
            department = matched
        } catch {
            loadFailed = true
        }
    }
}

/// 线上问诊第二步：医生选择页面
/// 设计参考图片：顶部科室切换+排序、日期选择栏、医生卡片（头像、姓名、职称、科室、擅长、价格、评分、就诊人数、余号）
struct ConsultDoctorSelectView: View {
    @StateObject private var viewModel: ConsultDoctorSelectViewModel
    @ObservedObject private var routeStore: AppRouteStore

    private let hospital: HospitalSummary
    private let department: HospitalDepartmentSummary

    @State private var selectedDateIndex = 0

    init(
        dependencies: HospitalCareFeatureDependencies,
        hospital: HospitalSummary,
        department: HospitalDepartmentSummary,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        routeStore: AppRouteStore
    ) {
        self.hospital = hospital
        self.department = department
        self.routeStore = routeStore
        _viewModel = StateObject(
            wrappedValue: ConsultDoctorSelectViewModel(
                dependencies: dependencies,
                hospital: hospital,
                department: department,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore
            )
        )
    }

    private let weekDays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    private var dateOptions: [(weekday: String, date: String, hasSlots: Bool)] {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        var options: [(weekday: String, date: String, hasSlots: Bool)] = []
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                let weekday = calendar.component(.weekday, from: date) - 1
                let dateStr = formatter.string(from: date)
                let hasSlots = i < 5 // 前5天有号
                if i == 0 {
                    options.append(("全部医生", "", hasSlots))
                } else {
                    options.append((weekDays[weekday], dateStr, hasSlots))
                }
            }
        }
        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部科室切换与排序
            topBar
            // 日期选择栏
            dateSelectionBar
            // 医生列表
            doctorList
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("线上复诊")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.onAppear() }
    }

    private var topBar: some View {
        HStack {
            Button {
                // 切换科室（暂时只显示当前科室）
            } label: {
                HStack(spacing: 4) {
                    Text(department.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                // 排序切换
            } label: {
                HStack(spacing: 4) {
                    Text("默认排序")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    private var dateSelectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(dateOptions.enumerated()), id: \.offset) { index, option in
                    DateSelectionButton(
                        weekday: option.weekday,
                        date: option.date,
                        hasSlots: option.hasSlots,
                        isSelected: selectedDateIndex == index
                    ) {
                        selectedDateIndex = index
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var doctorList: some View {
        Group {
            if viewModel.isLoading && viewModel.cards.isEmpty {
                ProgressView("正在加载医生…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.cards.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("该科室暂未接入问诊医生")
                        .foregroundStyle(.secondary)
                    if viewModel.loadError != nil {
                        Button("重试") { Task { await viewModel.reload() } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.cards.enumerated()), id: \.element.id) { index, card in
                            DoctorCardView(card: card, departmentName: department.name) {
                                routeStore.route(to: .hospitalConsultForm(agentID: card.id))
                            }
                            if index < viewModel.cards.count - 1 {
                                Divider()
                                    .padding(.leading, 88)
                            }
                        }
                    }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
        }
    }
}

// MARK: - 日期选择按钮
private struct DateSelectionButton: View {
    let weekday: String
    let date: String
    let hasSlots: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                if date.isEmpty == false {
                    Text(date)
                        .font(.headline)
                        .fontWeight(isSelected ? .bold : .regular)
                }
                Text(hasSlots ? "有号" : "无号")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : (hasSlots ? Color(uiColor: .systemPurple) : .secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color(uiColor: .systemPurple) : Color.clear)
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? Color(uiColor: .systemPurple) : .primary)
            .frame(width: 72, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color(uiColor: .systemPurple).opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color(uiColor: .systemPurple) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 医生卡片
private struct DoctorCardView: View {
    let card: HospitalAgentCard
    let departmentName: String
    let onTap: () -> Void

    // 模拟数据（实际应从后端获取）
    private var consultationPrice: String { "¥ 12.00" }
    private var rating: String { "5.0" }
    private var patientCount: String { "158" }
    private var remainingSlots: String { "余19/总20" }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // 头像
                HospitalAvatarImageView(
                    urlString: card.avatarURL.isEmpty ? card.doctorAvatarURL : card.avatarURL,
                    size: 64,
                    shape: .roundedSquare(ratio: 0.12),
                    placeholderText: String(card.doctorDisplayName.prefix(1)),
                    accent: Color(uiColor: .systemTeal)
                )

                // 信息区域
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            // 姓名 + 职称
                            HStack(spacing: 8) {
                                Text(card.doctorDisplayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                if card.doctorTitle.isEmpty == false {
                                    Text(card.doctorTitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // 科室
                            Text(departmentName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            // 擅长
                            if card.specialties.isEmpty == false {
                                Text("擅长：\(card.specialties.joined(separator: "、"))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        // 余号标签
                        Text(remainingSlots)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemGreen))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    // 底部信息：价格、评分、就诊人数
                    HStack(spacing: 16) {
                        Text(consultationPrice)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: .systemOrange))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .systemOrange))
                            Text(rating)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(Color(uiColor: .systemOrange))
                            Text(patientCount)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class ConsultDoctorSelectViewModel: ObservableObject {
    @Published private(set) var cards: [HospitalAgentCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let dependencies: HospitalCareFeatureDependencies
    private let hospital: HospitalSummary
    private let department: HospitalDepartmentSummary
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private var hasLoadedOnce = false

    init(
        dependencies: HospitalCareFeatureDependencies,
        hospital: HospitalSummary,
        department: HospitalDepartmentSummary,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore
    ) {
        self.dependencies = dependencies
        self.hospital = hospital
        self.department = department
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
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
            cards = try await dependencies.loadDirectory.loadAgents(
                accountID: session.accountID,
                hospitalID: hospital.id,
                departmentID: department.id,
                keyword: "",
                memberID: memberContextStore.context.selectedMemberID
            )
        } catch {
            loadError = "医生列表加载失败，请稍后重试"
        }
    }
}
