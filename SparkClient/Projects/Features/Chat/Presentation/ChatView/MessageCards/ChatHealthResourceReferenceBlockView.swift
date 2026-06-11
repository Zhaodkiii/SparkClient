import SwiftUI

struct ChatHealthResourceReferenceBlockView: View {
    let payload: ChatHealthResourceReferencePayload
    let totalRefs: Int
    let medicalQueryAPI: SparkMedicalQueryAPI
    let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onUnavailableTap: () -> Void
    let destinationBuilder: (HealthResourceReference) -> AnyView

    @StateObject private var viewModel: ChatHealthResourceReferenceCardViewModel

    init(
        payload: ChatHealthResourceReferencePayload,
        totalRefs: Int,
        medicalQueryAPI: SparkMedicalQueryAPI,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        onUnavailableTap: @escaping () -> Void,
        destinationBuilder: @escaping (HealthResourceReference) -> AnyView
    ) {
        self.payload = payload
        self.totalRefs = totalRefs
        self.medicalQueryAPI = medicalQueryAPI
        self.cachedCompleteData = cachedCompleteData
        self.onUnavailableTap = onUnavailableTap
        self.destinationBuilder = destinationBuilder
        _viewModel = StateObject(
            wrappedValue: ChatHealthResourceReferenceCardViewModel(
                payload: payload,
                totalRefs: totalRefs,
                medicalQueryAPI: medicalQueryAPI,
                cachedCompleteData: cachedCompleteData
            )
        )
    }

    var body: some View {
        let summary = viewModel.summary
        Group {
            switch summary.status {
            case .loaded:
                MainNavigationLink {
                    destinationBuilder(HealthResourceReference(payload))
                } label: {
                    cardLabel(summary: summary, showChevron: true)
                }
                .buttonStyle(.plain)
            case .failed:
                Button {
                    Task { await viewModel.retry() }
                } label: {
                    cardLabel(summary: summary, showChevron: false)
                }
                .buttonStyle(.plain)
            case .notFound:
                Button(action: onUnavailableTap) {
                    cardLabel(summary: summary, showChevron: false)
                }
                .buttonStyle(.plain)
            case .idle, .loading:
                cardLabel(summary: summary, showChevron: false)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .accessibilityLabel(
            String(
                format: L10n.text("chat.ask_report.message_card.accessibility"),
                summary.title
            )
        )
    }

    @ViewBuilder
    private func cardLabel(summary: HealthResourceCardSummary, showChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.typeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if totalRefs > 1 {
                        Text(summary.indexText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.status == .notFound ? .secondary : .primary)
                    .lineLimit(2)

                if let date = summary.dateText, let org = summary.organizationText {
                    Text("\(date) · \(org)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let date = summary.dateText {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let org = summary.organizationText {
                    Text(org)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                statusLine(summary: summary)

                if summary.badgeTexts.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(summary.badgeTexts, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                        }
                    }
                }
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            if summary.status == .loading {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private func statusLine(summary: HealthResourceCardSummary) -> some View {
        switch summary.status {
        case .idle, .loading:
            Text(L10n.text("chat.ask_report.message_card.loading"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .loaded:
            if let text = summary.summaryText, text.isEmpty == false {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let count = summary.attachmentCount, count > 0 {
                Text(
                    String(
                        format: L10n.text("chat.ask_report.message_card.attachment_count_format"),
                        count
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .notFound:
            Text(L10n.text("chat.ask_report.message_card.unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(L10n.text("chat.ask_report.message_card.retry"))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
