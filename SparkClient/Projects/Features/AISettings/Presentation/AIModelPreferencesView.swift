import SwiftUI

struct AIModelPreferencesView: View {
    enum Focus {
        case embedding
        case voice
        case optimization
    }

    @Binding var userInfo: UserInfo
    let focus: Focus

    var body: some View {
        Form {
            switch focus {
            case .embedding:
                Section(L10n.text("ai_settings.row.embedding")) {
                    TextField(
                        L10n.text("ai_settings.field.embedding_model"),
                        text: $userInfo.chooseEmbeddingModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            case .voice:
                Section(L10n.text("ai_settings.row.voice")) {
                    TextField(
                        L10n.text("ai_settings.field.voice_model"),
                        text: $userInfo.textToSpeechModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            case .optimization:
                Section(L10n.text("ai_settings.row.optimization")) {
                    TextField(
                        L10n.text("ai_settings.field.optimization_text_model"),
                        text: $userInfo.optimizationTextModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    TextField(
                        L10n.text("ai_settings.field.optimization_visual_model"),
                        text: $userInfo.optimizationVisualModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
        }
        .navigationTitle(title)
    }

    private var title: String {
        switch focus {
        case .embedding:
            return L10n.text("ai_settings.row.embedding")
        case .voice:
            return L10n.text("ai_settings.row.voice")
        case .optimization:
            return L10n.text("ai_settings.row.optimization")
        }
    }
}
