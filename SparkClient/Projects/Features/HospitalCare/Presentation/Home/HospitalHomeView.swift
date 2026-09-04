import SwiftUI

/// IOS26-TABBAR-000009：医院服务首页——"医院官方健康服务大厅"。
/// 职责边界：只做医院服务发现与导航；不复制消息列表、ChatThread、报告解读小任务或医生智能体模型。
struct HospitalHomeView: View {
    @StateObject private var viewModel: HospitalHomeViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    private let homeDependencies: HomeFeatureDependencies
    private let onOpenReportInterpretation: () -> Void
    private let onOpenDirectory: (UUID?) -> Void
    private let onOpenThread: (UUID) -> Void

    @State private var alertItem: HospitalHomeAlertItem?

    init(
        dependencies: HospitalCareFeatureDependencies,
        homeDependencies: HomeFeatureDependencies,
        onOpenReportInterpretation: @escaping () -> Void,
        onOpenDirectory: @escaping (UUID?) -> Void,
        onOpenThread: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: HospitalHomeViewModel(
                dependencies: dependencies,
                memberContextStore: homeDependencies.memberContextStore,
                sessionStore: homeDependencies.sessionStore
            )
        )
        self.memberContextStore = homeDependencies.memberContextStore
        self.homeDependencies = homeDependencies
        self.onOpenReportInterpretation = onOpenReportInterpretation
        self.onOpenDirectory = onOpenDirectory
        self.onOpenThread = onOpenThread
    }

    private var accent: Color { Color(uiColor: .systemTeal) }

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                skeletonContent
            case .unavailable:
                unavailableContent
            case .ready:
                readyContent
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // 通知铃铛由 MainTabCoordinatorView 通用工具栏承载；隐藏导航栏背景使头图延伸到顶部。
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await viewModel.onAppear() }
        .onChange(of: memberContextStore.context.selectedMemberID) { _ in
            // Q14：切换成员后刷新与患者相关的内容（医生卡片的最近会话归属），保留页面位置。
            Task { await viewModel.reloadAgentsForCurrentMember() }
        }
        .alert(item: $alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("知道了"))
            )
        }
        .alert(
            "无法开始咨询",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if $0 == false { viewModel.actionError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    // MARK: - 默认态（原型 §2）

    private var readyContent: some View {
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stretchyHeader(topInset: outer.safeAreaInsets.top)
                    freshnessBanner
                    patientSection
                    serviceSection
                    departmentSection
                    doctorSection
                    tcmFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .coordinateSpace(name: Self.scrollCoordinateSpace)
            .ignoresSafeArea(.container, edges: .top)
            .refreshable { await viewModel.retry() }
        }
    }

    // MARK: - 可拉伸头图（Stretchy Header，原型 §2.1）
    //
    // 只有"医院建筑背景图"参与下拉拉伸：通过 GeometryReader 读取滚动坐标系中的下拉偏移量，
    // 将偏移量换算为图片高度增量并整体上移，使图片顶部始终贴合屏幕顶端、底部随内容下移；
    // Logo/医院名称/通知按钮保持正常比例，随页面自然下移；松手后由 ScrollView 弹性回弹复位。

    private static let scrollCoordinateSpace = "hospitalHomeScroll"
    /// 头图静止高度（不含顶部安全区）。
    private static let headerHeight: CGFloat = 140

    private func stretchyHeader(topInset: CGFloat) -> some View {
        let totalHeight = Self.headerHeight + topInset
        return GeometryReader { proxy in
            let stretch = max(0, proxy.frame(in: .named(Self.scrollCoordinateSpace)).minY)
            ZStack(alignment: .top) {
                // 背景图：唯一参与拉伸的元素
                Image("hospitalHeaderBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: totalHeight + stretch)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color(uiColor: .systemGroupedBackground).opacity(0.55), location: 0.62),
                                .init(color: Color(uiColor: .systemGroupedBackground), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .offset(y: -stretch)

                // 头部内容：不缩放，随页面自然下移
                hospitalHeader
                    .padding(.horizontal, 16)
                    .padding(.top, topInset + 8)
            }
        }
        .frame(height: totalHeight)
        .padding(.horizontal, -16) // 抵消外层水平内边距，让背景图全宽
    }

    /// Q19：缓存状态轻量提示，不阻断浏览、不降低主要内容视觉层级。
    @ViewBuilder
    private var freshnessBanner: some View {
        switch viewModel.freshness {
        case .live:
            EmptyView()
        case .cachedRefreshing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("已使用缓存数据，正在更新")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .cachedStale:
            HStack(spacing: 8) {
                Text("当前显示上次数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("重试") {
                    Task { await viewModel.retry() }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// 原型 §2.1：医院身份行；右上角通知铃铛由 MainTabCoordinatorView 通用工具栏承载。
    private var hospitalHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            hospitalLogo
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.hospital?.name ?? "天长市中医院")
                    .font(.title.weight(.bold))
                    .lineLimit(1)
                Text("官方医疗服务")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var hospitalLogo: some View {
        Image("hospitalLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    /// 原型 §2.2：当前就诊人卡片；整卡与"切换"均打开现有成员切换组件（Q14）。
    private var patientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前就诊人")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            patientCard
        }
    }

    @ViewBuilder
    private var patientCard: some View {
        let members = memberContextStore.context.members
        let selectedMemberID = memberContextStore.context.selectedMemberID
        let resolvedMember: Member? = {
            if let selectedMemberID {
                return members.first(where: { $0.id == selectedMemberID }) ?? members.first
            }
            return members.first
        }()

        MemberProfileBindingMenu(
            memberContextStore: memberContextStore,
            selectedMemberID: selectedMemberID,
            homeDependencies: homeDependencies,
            onSelect: { memberID in
                guard let memberID, memberID != selectedMemberID else { return }
                memberContextStore.select(memberID: memberID)
            }
        ) {
            HStack(spacing: 12) {
                Group {
                    if resolvedMember != nil {
                        Image("avatarPatient")
                            .resizable()
                            .scaledToFill()
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.14))
                            .overlay {
                                Text("+")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                            }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedMember?.name ?? "添加就诊人")
                        .font(.title3)
                        .lineLimit(1)
                    if let subtitle = patientSubtitle(for: resolvedMember) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("切换")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前就诊人，\(resolvedMember?.name ?? "未设置")，点击切换")
    }

    private func patientSubtitle(for member: Member?) -> String? {
        guard let member else { return "选择或添加就诊人后使用医院服务" }
        var parts: [String] = []
        switch member.gender.lowercased() {
        case "male": parts.append("男")
        case "female": parts.append("女")
        default: break
        }
        if let birthDate = member.birthDate,
           let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year {
            parts.append("\(years) 岁")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 四项核心服务（原型 §2.3，Q4–Q7/Q20）

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("医院服务")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(HospitalHomeService.allCases) { service in
                    serviceCard(service)
                }
            }
        }
    }

    private func serviceCard(_ service: HospitalHomeService) -> some View {
        Button {
            handleServiceTap(service)
        } label: {
            VStack(spacing: 6) {
                Image(service.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if service.isHighlighted {
                            Text("AI")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(service.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(service.statusText)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background {
                if service.isHighlighted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accent, Color.accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                }
            }
            .foregroundStyle(service.isHighlighted ? Color.white : Color.primary)
            .overlay {
                if service.isHighlighted == false {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.title)，\(service.statusText)")
    }

    private func handleServiceTap(_ service: HospitalHomeService) {
        switch service {
        case .reportInterpretation:
            // Q7–Q9：复用已有"新建会话 → 自动发送报告解读小任务 → 报告上传卡片"流程。
            onOpenReportInterpretation()
        case .registration, .aiTriage, .telemedicine:
            // Q5–Q7：未开放服务仅提示，不创建 Thread、不进入空页面。
            alertItem = HospitalHomeAlertItem(
                title: service.title,
                message: "功能正在实现，敬请期待"
            )
        }
    }

    // MARK: - 常用科室（原型 §4，Q10）

    private var departmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "常用科室") {
                onOpenDirectory(nil)
            }
            HStack(spacing: 10) {
                ForEach(HospitalFeaturedDepartment.all) { department in
                    departmentCard(department)
                }
            }
        }
    }

    private func departmentCard(_ department: HospitalFeaturedDepartment) -> some View {
        Button {
            // Q10/原型 §4：匹配到真实科室 ID 才进入目录筛选，否则提示不可用，不伪造筛选结果。
            if let matched = department.match(in: viewModel.departments) {
                onOpenDirectory(matched.id)
            } else {
                alertItem = HospitalHomeAlertItem(
                    title: department.name,
                    message: "该科室暂未接入，敬请期待"
                )
            }
        } label: {
            VStack(spacing: 6) {
                Image(department.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Text(department.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(department.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("科室，\(department.name)")
    }

    // MARK: - 院内医生智能体（原型 §5，Q11–Q13）

    private var doctorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "院内医生智能体") {
                onOpenDirectory(nil)
            }
            if viewModel.featuredAgents.isEmpty {
                Text("暂无已发布的医生智能体")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(viewModel.featuredAgents) { card in
                        doctorCard(card)
                    }
                    // 不足 3 位时占位对齐，不补演示医生（补足策略待工单第 32 节确认）。
                    if viewModel.featuredAgents.count < 3 {
                        ForEach(0 ..< (3 - viewModel.featuredAgents.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func doctorCard(_ card: HospitalAgentCard) -> some View {
        Button {
            openAgentCard(card)
        } label: {
            VStack(spacing: 6) {
                doctorAvatar(card)
                Text(card.doctorDisplayName)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text([card.doctorTitle, card.departmentName]
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if card.specialties.isEmpty == false {
                    Text(card.specialties.prefix(2).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Group {
                    if viewModel.openingAgentID == card.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("去问 AI 助手")
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(accent.opacity(0.14), in: Capsule())
                .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.openingAgentID != nil)
        .accessibilityLabel("\(card.doctorDisplayName)，\(card.doctorTitle)，\(card.departmentName)，医生智能体，去问 AI 助手")
    }

    private func doctorAvatar(_ card: HospitalAgentCard) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HospitalAvatarImageView(
                urlString: card.avatarURL,
                size: 52,
                placeholderAsset: "avatarDoctor",
                accent: accent
            )

            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(accent, in: Circle())
                .offset(x: 2, y: 2)
        }
    }

    private func openAgentCard(_ card: HospitalAgentCard) {
        Task {
            if let threadID = await viewModel.openAgent(card) {
                onOpenThread(threadID)
            }
        }
    }

    // MARK: - 中医药页脚（原型底部"传承中医精华 守护百姓健康"）

    private var tcmFooter: some View {
        ZStack {
            Image("decorationTcm")
                .resizable()
                .scaledToFill()
            Text("传承中医精华  守护百姓健康")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.30, blue: 0.20))
                .shadow(color: .white.opacity(0.7), radius: 2, y: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("传承中医精华，守护百姓健康")
    }

    // MARK: - 通用区块头

    private func sectionHeader(title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: action) {
                HStack(spacing: 2) {
                    Text("查看全部")
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)，查看全部")
        }
    }

    // MARK: - 首次加载骨架（原型 §7.1）

    private var skeletonContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                skeletonBlock(height: 56)
                skeletonBlock(height: 76)
                HStack(spacing: 10) {
                    ForEach(0 ..< 4, id: \.self) { _ in skeletonBlock(height: 92) }
                }
                HStack(spacing: 10) {
                    ForEach(0 ..< 3, id: \.self) { _ in skeletonBlock(height: 92) }
                }
                HStack(spacing: 10) {
                    ForEach(0 ..< 3, id: \.self) { _ in skeletonBlock(height: 168) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func skeletonBlock(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.4)
            }
    }

    // MARK: - 无缓存且服务失败（原型 §7.4，Q18）

    private var unavailableContent: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cross.case")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("医院服务暂不可用")
                .font(.title3)
            Text("请稍后重试或检查网络连接")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - 页面动作与固定配置

/// 未开放服务/通知占位的统一提示（原型 §3、§6）。
private struct HospitalHomeAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Q4/Q7/Q20：四项核心服务横向四列同屏；可用状态由展示投影统一表达，页面只负责渲染与路由。
private enum HospitalHomeService: String, CaseIterable, Identifiable {
    case registration
    case aiTriage
    case reportInterpretation
    case telemedicine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .registration: return "预约挂号"
        case .aiTriage: return "AI 导诊"
        case .reportInterpretation: return "报告解读"
        case .telemedicine: return "线上问诊"
        }
    }

    var statusText: String {
        switch self {
        case .reportInterpretation: return "进入报告解读对话"
        case .registration, .aiTriage, .telemedicine: return "功能正在实现"
        }
    }

    var imageName: String {
        switch self {
        case .registration: return "iconRegistration"
        case .aiTriage: return "iconAiTriage"
        case .reportInterpretation: return "iconReport"
        case .telemedicine: return "iconTelemedicine"
        }
    }

    /// Q6：AI 导诊保持主视觉高亮，同时带"功能正在实现"状态。
    var isHighlighted: Bool {
        self == .aiTriage
    }
}

/// Q10：首页固定展示心内科、皮肤科、内分泌科（Dome 固定内容，内部标注演示来源）。
/// 点击时按关键字匹配服务端真实科室；匹配不到则提示不可用，不伪造筛选结果。
private struct HospitalFeaturedDepartment: Identifiable {
    let name: String
    let subtitle: String
    let imageName: String
    let matchKeywords: [String]

    var id: String { name }

    /// Dome 固定三科室；数据来源：需求工单 Q10（演示固定配置，非服务端动态排序）。
    static let all: [HospitalFeaturedDepartment] = [
        HospitalFeaturedDepartment(name: "心内科", subtitle: "心血管疾病", imageName: "iconCardiology", matchKeywords: ["心内"]),
        HospitalFeaturedDepartment(name: "皮肤科", subtitle: "皮肤与性病", imageName: "iconDermatology", matchKeywords: ["皮肤"]),
        HospitalFeaturedDepartment(name: "内分泌科", subtitle: "代谢与内分泌", imageName: "iconEndocrinology", matchKeywords: ["内分泌"])
    ]

    func match(in departments: [HospitalDepartmentSummary]) -> HospitalDepartmentSummary? {
        if let exact = departments.first(where: { $0.name == name }) {
            return exact
        }
        return departments.first(where: { department in
            matchKeywords.contains { department.name.contains($0) }
        })
    }
}
