import SwiftUI

struct HospitalAgentDirectoryView: View {
    @StateObject private var viewModel: HospitalAgentDirectoryViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    let onOpenThread: (UUID) -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        initialDepartmentID: UUID? = nil,
        onOpenThread: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: HospitalAgentDirectoryViewModel(
                dependencies: dependencies,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore,
                initialDepartmentID: initialDepartmentID
            )
        )
        self.memberContextStore = memberContextStore
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField
            departmentChips
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.keyword) { text in
            viewModel.updateKeyword(text)
        }
        .onChange(of: memberContextStore.context.selectedMemberID) { _ in
            Task { await viewModel.retry() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hospital.map { "\($0.name) · 院内名医" } ?? "院内名医")
                .font(.headline)
            Text("选择医生智能体开始咨询。AI 提供健康信息，不替代诊断。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索医生、职称、科室", text: $viewModel.keyword)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var departmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", selected: viewModel.selectedDepartmentID == nil) {
                    Task { await viewModel.selectDepartment(nil) }
                }
                ForEach(viewModel.departments) { department in
                    chip(title: department.name, selected: viewModel.selectedDepartmentID == department.id) {
                        Task { await viewModel.selectDepartment(department.id) }
                    }
                }
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("正在加载院内名医…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            statusCopy(
                title: "院内名医暂不可用",
                message: "请先登录后再查看院内名医目录。"
            )
        case .demoHospitalMissing:
            statusCopy(
                title: "院内名医暂不可用",
                message: "演示医院尚未配置，请联系管理员完成医院配置后重试。",
                retry: true
            )
        case .failed(let message):
            statusCopy(
                title: "医院目录加载失败",
                message: "\(message)。可下拉或点击重试，不会切换到其他医院或普通对话。",
                retry: true
            )
        case .empty:
            statusCopy(title: "该科室暂无医生智能体", message: "试试其他科室，或清空搜索后再看全部名医。")
        case .ready:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.cards) { card in
                        HospitalAgentCardView(
                            card: card,
                            hospitalName: viewModel.hospital?.name ?? "",
                            isOpening: viewModel.openingAgentID == card.id,
                            onOpen: {
                                Task {
                                    if let threadID = await viewModel.openCard(card) {
                                        onOpenThread(threadID)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable {
                await viewModel.retry()
            }
        }
    }

    private func statusCopy(title: String, message: String, retry: Bool = false) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if retry {
                Button("重试") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 48)
    }
}

private struct HospitalAgentCardView: View {
    let card: HospitalAgentCard
    let hospitalName: String
    let isOpening: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.doctorDisplayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        aiBadge
                    }
                    Text([card.doctorTitle, card.departmentName]
                        .filter { $0.isEmpty == false }
                        .joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if card.name.isEmpty == false {
                        Text(card.name)
                            .font(.headline)
                            .foregroundStyle(accent)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            if card.specialties.isEmpty == false {
                Label {
                    Text(card.specialties.prefix(3).joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "heart.text.square")
                        .font(.title3)
                        .imageScale(.medium)
                        .foregroundStyle(accent)
                }
            }

            Label("由医生团队维护", systemImage: "checkmark.shield")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                NavigationLink {
                    DoctorLightProfileView(
                        agentID: card.id,
                        hospitalName: hospitalName,
                        consultActionTitle: card.ctaTitle,
                        onConsult: onOpen
                    )
                } label: {
                    Label("查看详情", systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(accent)

                Button(action: onOpen) {
                    if isOpening {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(card.ctaTitle, systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(isOpening)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.doctorDisplayName)，\(card.doctorTitle)，\(card.departmentName)，医生智能体")
    }

    private var accent: Color { Color(uiColor: .systemTeal) }

    private var aiBadge: some View {
        Label("AI助手", systemImage: "sparkles")
            .font(.caption)
            .fontWeight(.semibold)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accent, in: Capsule())
            .fixedSize()
    }

    @ViewBuilder
    private var avatar: some View {
        HospitalAvatarImageView(
            urlString: card.avatarURL,
            size: 72,
            placeholderText: String(card.name.prefix(1)),
            accent: accent
        )
    }
}
