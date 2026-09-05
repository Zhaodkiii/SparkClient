import SwiftUI

/// 全局路由入口：只携带 agentID，回源医生卡片后再展示问诊材料填写页。
struct ConsultFormRouteView: View {
    private let dependencies: HospitalCareFeatureDependencies
    private let agentID: UUID
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private let onSubmitted: (HospitalConsultationDTO) -> Void

    @State private var agent: HospitalAgentCard?
    @State private var loadFailed = false

    init(
        dependencies: HospitalCareFeatureDependencies,
        agentID: UUID,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        onSubmitted: @escaping (HospitalConsultationDTO) -> Void
    ) {
        self.dependencies = dependencies
        self.agentID = agentID
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        Group {
            if let agent {
                ConsultFormView(
                    dependencies: dependencies,
                    agent: agent,
                    memberContextStore: memberContextStore,
                    sessionStore: sessionStore,
                    onSubmitted: onSubmitted
                )
            } else if loadFailed {
                VStack(spacing: 12) {
                    Spacer()
                    Text("医生信息暂不可用")
                        .font(.headline)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("正在加载问诊材料…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("填写问诊材料")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        agent = nil
        do {
            let dto = try await dependencies.remoteAPI.fetchAgent(agentID: agentID)
            if case .signedIn(let session) = sessionStore.state {
                dependencies.catalogCache.storeAgentDetail(dto, accountID: session.accountID)
            }
            agent = HospitalAgentCard(publicDTO: dto)
        } catch {
            loadFailed = true
        }
    }
}

/// 线上问诊第三步：填写问诊材料（参考原系统表单）。
///
/// 描述病情与病历资料必填；开单项目与补充病史选填。
/// 病历资料走公共 `MedicalDocumentFilePickerMenu`（拍摄 / 照片 / 文件），
/// 预览复用报告上传页的方形缩略图与 `unifiedFilePreview`。
struct ConsultFormView: View {
    @StateObject private var viewModel: ConsultFormViewModel

    private let agent: HospitalAgentCard
    private let onSubmitted: (HospitalConsultationDTO) -> Void

    @State private var showPreviewSheet = false
    @State private var previewIndex = 0

    init(
        dependencies: HospitalCareFeatureDependencies,
        agent: HospitalAgentCard,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        onSubmitted: @escaping (HospitalConsultationDTO) -> Void
    ) {
        self.agent = agent
        self.onSubmitted = onSubmitted
        _viewModel = StateObject(
            wrappedValue: ConsultFormViewModel(
                dependencies: dependencies,
                agent: agent,
                memberContextStore: memberContextStore,
                sessionStore: sessionStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                doctorHeader
                complaintSection
                attachmentSection
                orderItemSection
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("填写问诊材料")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            submitBar
        }
        .unifiedFilePreview(
            isPresented: $showPreviewSheet,
            files: viewModel.previewFiles,
            startIndex: previewIndex
        )
        .alert(
            "无法提交问诊",
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

    // MARK: - 各区块

    private var doctorHeader: some View {
        HStack(spacing: 12) {
            HospitalAvatarImageView(
                urlString: agent.avatarURL.isEmpty ? agent.doctorAvatarURL : agent.avatarURL,
                size: 48,
                placeholderText: String(agent.doctorDisplayName.prefix(1)),
                accent: Color(uiColor: .systemTeal)
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.doctorDisplayName)
                        .font(.headline)
                    if agent.doctorTitle.isEmpty == false {
                        Text(agent.doctorTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text([agent.departmentName, agent.name].filter { $0.isEmpty == false }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var complaintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("描述病情", required: true)
            ZStack(alignment: .topLeading) {
                if viewModel.chiefComplaint.isEmpty {
                    Text("请详细描述您目前的病情、本次问诊的目的，以便医生能够提前了解，为您提供更有效的治疗服务。")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $viewModel.chiefComplaint)
                    .frame(minHeight: 110)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .scrollContentBackground(.hidden)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("上传病历资料", required: true)
            Text("本次病情相关病历、诊断证明、检查报告等资料是医生确认接诊的重要依据，请务必准确上传。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.drafts.isEmpty == false {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    ForEach(Array(viewModel.drafts.enumerated()), id: \.element.id) { index, draft in
                        attachmentPreviewCard(draft: draft, index: index)
                    }
                }
            }

            if viewModel.remainingAttachmentSlots > 0 {
                MedicalDocumentFilePickerMenu(
                    maxPhotoSelectionCount: viewModel.remainingAttachmentSlots
                ) {
                    dashedAddFilesLabel
                } onFilesSelected: { files in
                    Task { await viewModel.addFiles(files) }
                }
            }
        }
    }

    private func attachmentPreviewCard(draft: ConsultAttachmentDraft, index: Int) -> some View {
        MedicalDocumentFilePreviewSquareCard(
            item: draft.file.previewInput,
            onPreview: {
                previewIndex = index
                showPreviewSheet = true
            },
            onDelete: { viewModel.remove(draftID: draft.id) }
        )
        .overlay {
            switch draft.status {
            case .uploading(let progress):
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                    VStack(spacing: 6) {
                        ProgressView(value: progress)
                            .tint(.white)
                            .frame(width: 36)
                        Text("上传中")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    }
                }
            case .failed:
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                    Button {
                        Task { await viewModel.retry(draftID: draft.id) }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            Text("重试")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            case .ready:
                EmptyView()
            }
        }
    }

    /// 与首页报告上传页 `MedicalDocumentFilePickerMenu` 同一套拍摄 / 照片 / 文件入口。
    private var dashedAddFilesLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
            Text(L10n.text("medical.upload.picking.add_files"))
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Color.accentColor)
    }

    private var orderItemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("请选择开单项目", required: false)
            Text("如您已明确了解病情及需要的开单项目，可提前选择，便于医生快速审核。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ConsultFormViewModel.orderItemOptions, id: \.self) { option in
                    let selected = viewModel.orderItems.contains(option)
                    Button {
                        viewModel.toggleOrderItem(option)
                    } label: {
                        Text(option)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? Color(uiColor: .systemTeal).opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
                            .foregroundStyle(selected ? Color(uiColor: .systemTeal) : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(selected ? Color(uiColor: .systemTeal) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("补充病史信息", required: false)
            Text("便于医生全面了解病情，您可继续完善以下信息。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            historyField(title: "既往史", hint: "曾经有过相关病史，如有请如实填写", text: $viewModel.pastHistory)
            historyField(title: "家族史", hint: "家族相关的遗传病史，如有请如实填写", text: $viewModel.familyHistory)
            historyField(title: "过敏史", hint: "曾经有过的过敏病史，如有请如实填写", text: $viewModel.allergyHistory)
        }
    }

    private func historyField(title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("（\(hint)）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("无", text: text)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var submitBar: some View {
        VStack(spacing: 6) {
            if let validation = viewModel.validationHint {
                Text(validation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task {
                    if let consultation = await viewModel.submit() {
                        onSubmitted(consultation)
                    }
                }
            } label: {
                HStack {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(viewModel.isSubmitting ? "正在提交…" : "提交问诊")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemTeal))
            .disabled(viewModel.canSubmit == false || viewModel.isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(.bar)
    }

    private func sectionTitle(_ title: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(required ? "（必填）" : "（选填）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
