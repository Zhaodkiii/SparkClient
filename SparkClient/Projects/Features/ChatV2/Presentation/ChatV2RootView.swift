import SwiftUI

struct ChatV2RootView: View {
    @ObservedObject var viewModel: ChatV2ViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            threadStrip
            Divider()
            conversation
            composer
        }
        .navigationTitle("对话 V2")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.bootstrapIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("全新持久化链路")
                    .font(.headline)
                Text("页面、存储、对话流程与旧版完全隔离")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.createThread() }
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var threadStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.threads) { thread in
                    Button {
                        Task { await viewModel.selectThread(thread.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title)
                                .font(.subheadline.weight(.semibold))
                            Text(thread.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minWidth: 120, alignment: .leading)
                        .background(thread.id == viewModel.selectedThreadID ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.displayMessages.isEmpty {
                        VStack(spacing: 8) {
                            Text("对话 V2 已准备好")
                                .font(.headline)
                            Text("发送一条消息，系统会走新的快照式持久化流程，并生成睡眠卡片。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 80)
                        .padding(.horizontal, 24)
                    } else {
                        ForEach(viewModel.displayMessages) { message in
                            ChatV2MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: viewModel.displayMessages.count) { _ in
                if let lastID = viewModel.displayMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入任意内容，触发 V2 睡眠卡片链路", text: $viewModel.composerText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await viewModel.sendCurrentInput() }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }
}

private struct ChatV2MessageBubble: View {
    let message: ChatV2ViewModel.DisplayMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(message.document.nodes, id: \.id) { node in
                nodeView(node)
            }
            if message.isStreaming {
                Text("生成中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(message.role == .user ? Color.accentColor : Color(.systemBackground))
        .foregroundStyle(message.role == .user ? Color.white : Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func nodeView(_ node: ChatV2MessageNode) -> some View {
        switch node {
        case .text(let text):
            Text(text.text)
                .font(.body)
                .textSelection(.enabled)
        case .block(let block):
            blockView(block)
        }
    }

    @ViewBuilder
    private func blockView(_ block: ChatV2BlockNode) -> some View {
        switch block.payload {
        case .toolStatus(let payload):
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text(payload.toolName)
                        .font(.subheadline.weight(.semibold))
                    Text(payload.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .sleepVisualization(let payload):
            VStack(alignment: .leading, spacing: 8) {
                Text("睡眠分析卡片")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    metric("总睡眠", "\(payload.totalSleepMinutes) 分钟")
                    metric("深睡", "\(payload.deepSleepMinutes) 分钟")
                }
                HStack {
                    metric("核心", "\(payload.coreSleepMinutes) 分钟")
                    metric("REM", "\(payload.remSleepMinutes) 分钟")
                }
                Text("清醒 \(payload.awakeMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .knowledgeCards(let cards):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cards) { card in
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                    Text(card.content)
                        .font(.caption)
                }
            }
        case .taskCards(let cards):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cards) { card in
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                    Text(card.summary)
                        .font(.caption)
                }
            }
        case .mapRoute(let payload):
            VStack(alignment: .leading, spacing: 6) {
                Text("路线卡片")
                    .font(.subheadline.weight(.semibold))
                Text("地点数：\(payload.locations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .error(let payload):
            VStack(alignment: .leading, spacing: 6) {
                Text(payload.title)
                    .font(.subheadline.weight(.semibold))
                Text(payload.message)
                    .font(.caption)
            }
            .padding(12)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
