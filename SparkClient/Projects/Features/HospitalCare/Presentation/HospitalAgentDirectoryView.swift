import SwiftUI

struct HospitalAgentDirectoryView: View {
    @StateObject private var viewModel: HospitalAgentDirectoryViewModel
    @ObservedObject private var memberContextStore: MemberContextStore
    let onOpenThread: (UUID) -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        onOpenThread: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: HospitalAgentDirectoryViewModel(
                dependencies: dependencies,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore
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
    let isOpening: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(card.doctorDisplayName)
                                .font(.headline)
                            Text("医生智能体")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        Text([card.doctorTitle, card.departmentName].filter { $0.isEmpty == false }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if card.specialties.isEmpty == false {
                    Text("擅长：\(card.specialties.prefix(3).joined(separator: "、"))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if card.serviceBoundary.isEmpty == false {
                    Text(card.serviceBoundary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Spacer()
                    if isOpening {
                        ProgressView()
                    } else {
                        Text(card.ctaTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .accessibilityLabel("\(card.doctorDisplayName) \(card.ctaTitle)")
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = URL(string: card.doctorAvatarURL), card.doctorAvatarURL.isEmpty == false {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholderAvatar
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.16))
            .frame(width: 48, height: 48)
            .overlay {
                Text(String(card.doctorDisplayName.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            }
    }
}
