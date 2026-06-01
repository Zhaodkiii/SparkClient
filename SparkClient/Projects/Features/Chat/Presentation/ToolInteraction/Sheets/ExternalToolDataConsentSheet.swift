import SwiftUI

struct ExternalToolDataConsentSheet: View {
    let prompt: ExternalToolDataSharePrompt
    let onAllow: () -> Void
    let onAllowAlways: () -> Void
    let onDeny: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("chat.tool_consent.intro"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        providerGrid
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("chat.tool_consent.data_title"))
                            .font(.headline)
                        ForEach(prompt.dataLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(prompt.payloadBlocks) { block in
                        payloadBlockView(block)
                    }

                    if let url = prompt.privacyPolicyURL {
                        Link(destination: url) {
                            Label(L10n.text("chat.tool_consent.privacy"), systemImage: "lock.shield")
                        }
                    }

                    Text(L10n.text("chat.tool_consent.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(action: onAllowAlways) {
                        Label(L10n.text("chat.tool_consent.allow_always"), systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.tool_consent.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("chat.tool_consent.deny"), role: .cancel, action: onDeny)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("chat.tool_consent.allow"), action: onAllow)
                }
            }
        }
    }

    private var providerGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            providerRow(title: "Provider", value: prompt.providerCompany)
            providerRow(title: "Endpoint", value: prompt.endpointLine)
            providerRow(title: "Model", value: prompt.modelLine)
        }
        .font(.caption)
    }

    private func providerRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func payloadBlockView(_ block: ExternalToolDataSharePayloadBlock) -> some View {
        let argumentsDisplay = ToolLargeTextDisplay(
            text: block.argumentsText,
            emptyPlaceholder: "-",
            limit: ToolSheetDisplayLimits.maxArgumentChars
        )
        let resultDisplay = ToolLargeTextDisplay(
            text: block.resultText,
            emptyPlaceholder: "-",
            limit: ToolSheetDisplayLimits.maxResultChars
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(block.friendlyTitle)
                .font(.subheadline.weight(.semibold))
            Text(block.toolAPIName)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            DisclosureGroup(L10n.text("chat.tool_consent.arguments")) {
                ToolLargeTextPreview(display: argumentsDisplay)
            }
            DisclosureGroup(L10n.text("chat.tool_consent.result")) {
                ToolLargeTextPreview(display: resultDisplay)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
