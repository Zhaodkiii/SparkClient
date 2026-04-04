import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            await viewModel.loadIfNeeded()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if viewModel.isSending {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: viewModel.messages.count) { _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubbleContent(message)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleContent(message)
            }
        }
        .padding(.horizontal, 16)
    }

    private func bubbleContent(_ message: ChatMessage) -> some View {
        Text(message.content)
            .font(.body)
            .foregroundColor(message.role == .assistant ? .primary : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(message.role == .assistant ? Color(uiColor: .secondarySystemGroupedBackground) : Color.accentColor)
            )
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(L10n.text("chat.input.placeholder"), text: $viewModel.draftText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await viewModel.sendCurrentDraft()
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .topLeading) {
            Text("工具命令：/ocr <文件路径>  或  /confirm_draft")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .offset(y: -16)
        }
    }
}
