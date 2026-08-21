import SwiftUI

/// 新会话首条系统引导卡片：
/// 上半部分为可横向切换的健康数据滑块，下半部分为健康科普问题列表。
/// 纯渲染组件：数据全部来自 payload，点击回调上抛，不直接拉取网络或写 DB。
struct ChatGuideMessageCardView: View {
    let threadID: UUID
    let payload: ChatGuideCardPayload
    let onQuestionTap: (ChatGuideQuestion) -> Void

    /// 正在发送中的问题 id（用于按钮置灰防重入），由外部注入。
    var sendingQuestionIDs: Set<String> = []
    /// 滑块 → 健康首页 destination（CHAT-000025）；nil 时滑块降级为纯展示面板。
    var homeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil
    var metricSectionsProvider: ChatGuideMetricSectionsProvider? = nil
    /// 成员切换重新生成时使用不同 loading 文案。
    var isRegeneratingForNewMember: Bool = false
    var logger: Logger = ConsoleLogger()

    @State private var realtimeMetricSections: [ChatGuideMetricSection]?
    @State private var reloadGeneration = 0

    init(
        threadID: UUID = UUID(),
        payload: ChatGuideCardPayload,
        onQuestionTap: @escaping (ChatGuideQuestion) -> Void,
        sendingQuestionIDs: Set<String> = [],
        homeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil,
        metricSectionsProvider: ChatGuideMetricSectionsProvider? = nil,
        isRegeneratingForNewMember: Bool = false,
        logger: Logger = ConsoleLogger()
    ) {
        self.threadID = threadID
        self.payload = payload
        self.onQuestionTap = onQuestionTap
        self.sendingQuestionIDs = sendingQuestionIDs
        self.homeDestinationBuilder = homeDestinationBuilder
        self.metricSectionsProvider = metricSectionsProvider
        self.isRegeneratingForNewMember = isRegeneratingForNewMember
        self.logger = logger
    }

    private var displayedMetricSections: [ChatGuideMetricSection] {
        realtimeMetricSections ?? payload.metricSections
    }

    private var loadingTitle: String {
        if isRegeneratingForNewMember {
            return L10n.text(
                "chat.guide.questions.generating.new_member",
                fallback: "正在根据新成员资料生成科普问题..."
            )
        }
        return L10n.text(
            "chat.guide.questions.generating",
            fallback: "正在根据成员资料生成健康科普问题..."
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            ChatGuideMetricCarouselView(
                sections: displayedMetricSections,
                homeDestinationBuilder: homeDestinationBuilder,
                onPageChanged: { section in
                    logger.info(
                        "chat.guide.metrics.page_changed section=\(section.id)",
                        module: .general
                    )
                    Task {
                        await reloadMetricSections(reason: "page_changed")
                    }
                }
            )

            if payload.isShowingQuestionLoading {
                ChatGuideQuestionLoadingSectionView(loadingTitle: loadingTitle)
            } else {
                VStack(spacing: 12) {
                    ForEach(payload.questions, id: \.id) { question in
                        ChatGuideQuestionRowView(
                            question: question,
                            isDisabled: sendingQuestionIDs.contains(question.id)
                        ) {
                            onQuestionTap(question)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("chat.guide.card.accessibility.label", fallback: "健康对话引导卡片"))
        .task(id: threadID) {
            await reloadMetricSections(reason: "task")
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatGuideHealthBindingDidChange)) { _ in
            Task {
                await reloadMetricSections(reason: "binding_changed")
            }
        }
    }

    private func reloadMetricSections(reason: String) async {
        guard let metricSectionsProvider else { return }
        reloadGeneration &+= 1
        let requestGeneration = reloadGeneration
        logger.info(
            "chat.guide.metrics.reload_start thread=\(String(threadID.uuidString.prefix(8))) reason=\(reason) sequence=\(requestGeneration)",
            module: .general
        )
        let result = await metricSectionsProvider(threadID)
        guard !Task.isCancelled else { return }
        guard requestGeneration == reloadGeneration else {
            logger.info(
                "chat.guide.metrics.reload_skipped thread=\(String(threadID.uuidString.prefix(8))) reason=stale_request sequence=\(requestGeneration)",
                module: .general
            )
            return
        }
        guard let result else {
            logger.info(
                "chat.guide.metrics.reload_skipped thread=\(String(threadID.uuidString.prefix(8))) reason=thread_context_unavailable sequence=\(requestGeneration)",
                module: .general
            )
            return
        }
        guard result.threadID == threadID else {
            logger.info(
                "chat.guide.metrics.reload_skipped thread=\(String(threadID.uuidString.prefix(8))) reason=thread_mismatch sequence=\(requestGeneration)",
                module: .general
            )
            return
        }
        await MainActor.run {
            realtimeMetricSections = result.sections
        }
        logger.info(
            "chat.guide.metrics.reload_done thread=\(String(threadID.uuidString.prefix(8))) member=\(result.memberID.map(String.init) ?? "nil") reason=\(reason) sequence=\(requestGeneration) states=\(Self.sectionStateSummary(result.sections))",
            module: .general
        )
    }

    nonisolated private static func sectionStateSummary(_ sections: [ChatGuideMetricSection]) -> String {
        sections.map { "\($0.id):\($0.state.rawValue)" }.joined(separator: ",")
    }
}

#Preview("引导卡片-生成中") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.generatingPayload,
        onQuestionTap: { _ in }
    )
    .padding()
}

#Preview("引导卡片-Light") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
}

#Preview("引导卡片-Dark") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
    .background(Color(uiColor: .systemBackground))
    .preferredColorScheme(.dark)
}

#Preview("引导卡片-辅助功能大字号") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.fullPayload,
        onQuestionTap: { _ in }
    )
    .padding()
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("引导卡片-空数据") {
    ChatGuideMessageCardView(
        payload: ChatGuideCardPreviewFixtures.emptyPayload,
        onQuestionTap: { _ in }
    )
    .padding()
}
