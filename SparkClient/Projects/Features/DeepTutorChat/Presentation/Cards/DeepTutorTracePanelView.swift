import SwiftUI

struct DeepTutorTracePanelView: View {
    let message: DeepTutorMessage
    let payload: DeepTutorTraceBlockPayload
    let displayMode: DeepTutorToolTraceDisplayMode
    let collapseToolsWhileStreaming: Bool
    let onToolPreview: (DeepTutorToolPreviewPrompt) -> Void
    @State private var userPinnedExpansion: Bool?
    @State private var expandedToolIDs: Set<String> = []

    private var hasTrace: Bool {
        payload.rows.isEmpty == false
    }

    private var effectiveExpanded: Bool {
        guard hasTrace else { return false }
        if let userPinnedExpansion {
            return userPinnedExpansion
        }
        switch displayMode {
        case .expanded:
            return true
        case .collapsedAlways:
            return false
        case .collapsedAfterCompletion:
            if isStreaming, collapseToolsWhileStreaming == false {
                return true
            }
            return !payload.isFinalAnswerPhase
        }
    }

    private var isStreaming: Bool {
        payload.isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if effectiveExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(payload.rows) { row in
                        traceRow(row)
                    }
                }
                .padding(.leading, 11)
                .padding(.top, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(DeepTutorPalette.traceBorderColor)
                        .frame(width: 1)
                }
                .padding(.leading, 13)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 12)
        .onChange(of: message.id) { _ in
            userPinnedExpansion = nil
        }
        .onChange(of: payload.isFinalAnswerPhase) { oldValue, newValue in
            guard userPinnedExpansion == nil, oldValue == false, newValue else { return }
            DeepTutorChatLog.traceAutoCollapse(
                messageID: message.id,
                fromExpanded: true,
                reason: "final_answer_phase"
            )
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                let next = !effectiveExpanded
                userPinnedExpansion = next
                DeepTutorChatLog.traceUserToggle(messageID: message.id, expanded: next)
            }
        } label: {
            HStack(spacing: 10) {
                headerIcon
                    .foregroundStyle(Color.accentColor.opacity(0.9))

                Text(payload.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DeepTutorPalette.traceHeaderText)

                if let duration = DeepTutorTraceFormatter.formatDuration(payload.elapsedSeconds) {
                    Text(duration)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.55))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.45))
                    .rotationEffect(.degrees(effectiveExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(effectiveExpanded ? "展开" : "收起")
    }

    @ViewBuilder
    private var headerIcon: some View {
        if isStreaming {
            DeepTutorReasoningGlyph(size: 22)
        } else {
            DeepTutorRespondedGlyph(size: 22)
        }
    }

    @ViewBuilder
    private func traceRow(_ row: DeepTutorTraceRowModel) -> some View {
        switch row.kind {
        case .thinking:
            thinkingRow(row)
        case .askUser:
            askUserRow(row)
        case .tool, .error:
            toolRow(row)
        }
    }

    private func thinkingRow(_ row: DeepTutorTraceRowModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            rowIcon(row, active: false)
            if let detail = row.resultDetail {
                DeepTutorMarkdownRenderer(markdown: detail)
                    .font(.system(size: DeepTutorPalette.traceBodyFontSize))
                    .italic()
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
                    .lineSpacing(3)
            }
        }
        .padding(.vertical, 6)
    }

    private func askUserRow(_ row: DeepTutorTraceRowModel) -> some View {
        let isExpandable = row.argsDetail != nil || row.resultDetail != nil
        let isToolExpanded = expandedToolIDs.contains(row.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                rowIcon(row, active: row.status == .running)
                toolNameButton(for: row)
                if isExpandable {
                    expandButton(isExpanded: isToolExpanded) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            toggleToolExpansion(row.id)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            if isToolExpanded {
                toolDetail(for: row)
            }
        }
    }

    private func toolRow(_ row: DeepTutorTraceRowModel) -> some View {
        let isExpandable = row.argsDetail != nil || row.resultDetail != nil
        let isToolExpanded = expandedToolIDs.contains(row.id)
        let active = row.status == .running

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                rowIcon(row, active: active)
                VStack(alignment: .leading, spacing: 0) {
                    if let chip = row.chip, chip.isEmpty == false {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            toolNameButton(for: row, fixedSize: true)
                            Text(chip)
                                .font(.system(size: row.chipIsMonospaced ? 12.5 : 14, weight: .regular, design: row.chipIsMonospaced ? .monospaced : .default))
                                .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    } else {
                        toolNameButton(for: row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isExpandable {
                    expandButton(isExpanded: isToolExpanded) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            toggleToolExpansion(row.id)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            if isToolExpanded {
                toolDetail(for: row)
            }
        }
    }

    private func rowIcon(_ row: DeepTutorTraceRowModel, active: Bool) -> some View {
        DeepTutorTraceGlyph.from(iconKey: row.icon).view
            .foregroundStyle(active ? Color.accentColor.opacity(0.85) : DeepTutorPalette.traceMutedText.opacity(0.55))
            .frame(width: 15, height: 15)
            .padding(.top, 2)
    }

    private func toolDetail(for row: DeepTutorTraceRowModel) -> some View {
        DeepTutorToolDetailView(
            toolName: row.toolName ?? row.verb,
            argsDetail: row.argsDetail,
            resultDetail: row.resultDetail,
            resultIsMarkdown: row.resultIsMarkdown
        )
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }

    private func toggleToolExpansion(_ id: String) {
        if expandedToolIDs.contains(id) {
            expandedToolIDs.remove(id)
        } else {
            expandedToolIDs.insert(id)
        }
    }

    private func toolNameButton(for row: DeepTutorTraceRowModel, fixedSize: Bool = false) -> some View {
        Button {
            onToolPreview(DeepTutorToolPreviewRelatedContentMapper.makePrompt(message: message, row: row))
        } label: {
            Text(row.verb)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .lineLimit(2)
                .if(fixedSize) { view in
                    view.fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: fixedSize ? nil : .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func expandButton(isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.4))
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
