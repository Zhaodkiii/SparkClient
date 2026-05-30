import SwiftUI

struct SystemMessageSettingsSheet: View {
    let prompt: SystemMessageSettingsPrompt
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var useDefaultSystemMessage: Bool
    @State private var systemMessage: String
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false

    init(
        prompt: SystemMessageSettingsPrompt,
        onSave: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onSave = onSave
        self.onClose = onClose

        let session = prompt.sessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPrompt = prompt.defaultPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        _useDefaultSystemMessage = State(initialValue: session.isEmpty || session == defaultPrompt)
        _systemMessage = State(initialValue: session.isEmpty ? prompt.defaultPrompt : prompt.sessionPrompt)
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            Form {
                Section(L10n.text("chat.system_message.section.current_model")) {
                    Label(prompt.modelDisplayName, systemImage: prompt.isAgentModel ? "person.crop.circle" : "cpu")
                    if prompt.isAgentModel {
                        Text(L10n.text("chat.system_message.agent_model_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.text("chat.system_message.session_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if prompt.isAgentModel {
                    Section(L10n.text("chat.system_message.section.agent_prompt")) {
                        Text(agentPromptText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if prompt.sessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Section(L10n.text("chat.system_message.section.session_prompt")) {
                            Text(prompt.sessionPrompt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Section(L10n.text("chat.system_message.section.selection")) {
                        Picker(L10n.text("chat.system_message.picker.title"), selection: $useDefaultSystemMessage) {
                            Text(L10n.text("chat.system_message.option.default")).tag(true)
                            Text(L10n.text("chat.system_message.option.custom")).tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if useDefaultSystemMessage {
                        Section(L10n.text("chat.system_message.section.default_prompt")) {
                            Text(prompt.defaultPrompt)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Section(L10n.text("chat.system_message.section.edit_system_role")) {
                            PromptInputEditorView(
                                text: $systemMessage,
                                promptTemplates: prompt.promptTemplates,
                                onVoiceInput: { showVoiceInput = true },
                                onTextInput: { showTextInputDrawer = true }
                            )
                        }
                    }
                }

                Section(L10n.text("chat.system_message.section.description")) {
                    Text(L10n.text("chat.system_message.description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.text("chat.system_message.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(prompt.isAgentModel ? L10n.text("common.done") : L10n.text("common.cancel"), action: onClose)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save")) {
                        onSave(useDefaultSystemMessage ? prompt.defaultPrompt : systemMessage)
                    }
                    .disabled(prompt.isAgentModel)
                }
            }
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $systemMessage,
                isPresented: $showTextInputDrawer
            )
            .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $systemMessage,
                isPresented: $showVoiceInput
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }

    private var agentPromptText: String {
        let text = prompt.agentPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L10n.text("chat.system_message.agent_prompt_empty") : text
    }
}
