import SwiftUI

struct DeepTutorTracePanelView: View {
    let messageID: UUID
    let payload: DeepTutorTraceBlockPayload
    @State private var userPinnedExpansion: Bool?
    @State private var expandedToolIDs: Set<String> = []

    private var hasTrace: Bool {
        payload.rows.isEmpty == false
    }

    private var effectiveExpanded: Bool {
        guard hasTrace else { return false }
        return userPinnedExpansion ?? !payload.isFinalAnswerPhase
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
        .onChange(of: messageID) { _, _ in
            userPinnedExpansion = nil
        }
        .onChange(of: payload.isFinalAnswerPhase) { oldValue, newValue in
            guard userPinnedExpansion == nil, oldValue == false, newValue else { return }
            DeepTutorChatLog.traceAutoCollapse(
                messageID: messageID,
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
                DeepTutorChatLog.traceUserToggle(messageID: messageID, expanded: next)
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
            Button {
                guard isExpandable else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    toggleToolExpansion(row.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    rowIcon(row, active: row.status == .running)
                    Text(row.verb)
                        .font(.system(size: 14))
                        .foregroundStyle(DeepTutorPalette.traceMutedText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isExpandable {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.4))
                            .rotationEffect(.degrees(isToolExpanded ? 0 : -90))
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isExpandable == false)

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
            Button {
                guard isExpandable else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    toggleToolExpansion(row.id)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    rowIcon(row, active: active)
                    VStack(alignment: .leading, spacing: 0) {
                        if let chip = row.chip, chip.isEmpty == false {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.verb)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DeepTutorPalette.traceMutedText)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(chip)
                                    .font(.system(size: row.chipIsMonospaced ? 12.5 : 14, weight: .regular, design: row.chipIsMonospaced ? .monospaced : .default))
                                    .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.55))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else {
                            Text(row.verb)
                                .font(.system(size: 14))
                                .foregroundStyle(DeepTutorPalette.traceMutedText)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isExpandable {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DeepTutorPalette.traceMutedText.opacity(0.4))
                            .rotationEffect(.degrees(isToolExpanded ? 0 : -90))
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(isExpandable == false)

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
}
