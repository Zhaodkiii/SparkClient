import SwiftUI

struct GuestChatView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var sessionStore: GuestChatSessionStore
    @StateObject private var viewModel: GuestChatViewModel

    @State private var showConfigView = false
    @State private var showDisclaimer = true
    @State private var hasAcceptedDisclaimer = false
    @State private var draftText = ""

    init(aiClient: GuestAIChatClient) {
        let store = GuestChatSessionStore()
        _sessionStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: GuestChatViewModel(sessionStore: store, aiClient: aiClient))
    }

    var body: some View {
        Group {
            if hasAcceptedDisclaimer {
                if sessionStore.config != nil {
                    chatContent
                } else {
                    configPromptView
                }
            } else {
                Color(uiColor: .systemGroupedBackground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(L10n.text("guest.chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("guest.chat.exit")) {
                    exitGuestMode()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if sessionStore.config != nil {
                    Menu {
                        Button(L10n.text("guest.chat.settings")) {
                            showConfigView = true
                        }
                        Button(L10n.text("guest.chat.clear"), role: .destructive) {
                            viewModel.clearMessages()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showDisclaimer, onDismiss: handleDisclaimerDismiss) {
            GuestModeDisclaimerSheet(
                onContinue: {
                    hasAcceptedDisclaimer = true
                    showDisclaimer = false
                },
                onExit: {
                    showDisclaimer = false
                    exitGuestMode()
                }
            )
        }
        .sheet(isPresented: $showConfigView) {
            GuestAIConfigView(config: Binding(
                get: { sessionStore.config },
                set: { newConfig in
                    if let newConfig {
                        viewModel.applyConfig(newConfig)
                    } else {
                        sessionStore.config = nil
                        sessionStore.clearMessages()
                    }
                }
            ))
        }
        .onChange(of: sessionStore.config) { config in
            if config != nil {
                viewModel.appendWelcomeMessageIfNeeded()
            }
        }
    }

    private func exitGuestMode() {
        viewModel.exitGuestMode()
        dismiss()
    }

    private func handleDisclaimerDismiss() {
        guard hasAcceptedDisclaimer == false else { return }
        exitGuestMode()
    }

    private var configPromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text(L10n.text("guest.chat.config_prompt_title"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(L10n.text("guest.chat.config_prompt_body"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(L10n.text("guest.chat.start_config")) {
                showConfigView = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sessionStore.messages) { message in
                            GuestChatMessageRow(message: message)
                                .id(message.id)
                        }

                        if viewModel.isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(L10n.text("guest.chat.sending"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: sessionStore.messages.count) { _ in
                    if let lastID = sessionStore.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            composer
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L10n.text("guest.chat.input_placeholder"), text: $draftText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button {
                let text = draftText
                draftText = ""
                Task {
                    await viewModel.send(text: text)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
            }
            .disabled(viewModel.isSending || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .foregroundStyle(
                viewModel.isSending || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Color.secondary
                    : Color.accentColor
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct GuestChatMessageRow: View {
    let message: GuestChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, 16)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant, .system:
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

#Preview("Guest Chat - Config Prompt") {
    CompatibleNavigationContainer {
        GuestChatView(aiClient: PreviewGuestAIChatClient())
    }
}

private struct PreviewGuestAIChatClient: GuestAIChatClient {
    func send(messages: [GuestChatMessage], config: GuestAIConfig) async throws -> String {
        L10n.text("guest.chat.welcome")
    }
}
