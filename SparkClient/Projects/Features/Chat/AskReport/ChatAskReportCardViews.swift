import SwiftUI

// MARK: - Selection chrome

struct ChatAskReportSelectableCard<Content: View>: View {
    let isSelected: Bool
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                content()
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row cards

struct ChatAskReportMedicalCaseCard: View {
    let source: ChatSelectableHealthSource
    let isSelected: Bool
    let isExpanded: Bool
    let searchQuery: String
    let selectedSourceIDs: Set<String>
    let onSelectCase: () -> Void
    let onToggleExpand: () -> Void
    let onSelectChild: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChatAskReportSelectableCard(isSelected: isSelected, onTap: onSelectCase) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            highlightedText(source.title, query: searchQuery)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let subtitle = source.subtitle, subtitle.isEmpty == false {
                                highlightedText(subtitle, query: searchQuery)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let summary = source.summary, summary.isEmpty == false {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        if source.children.isEmpty == false {
                            Button(action: onToggleExpand) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let related = ChatAskReportRelatedCountFormatter.format(source) {
                        Text(related)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.text("chat.ask_report.resource_type.medical_case"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if isExpanded, source.children.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(source.children) { child in
                        ChatAskReportChildRow(
                            source: child,
                            isSelected: selectedSourceIDs.contains(child.selectionKey),
                            searchQuery: searchQuery,
                            onTap: { onSelectChild(child.selectionKey) }
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

struct ChatAskReportChildRow: View {
    let source: ChatSelectableHealthSource
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void

    var body: some View {
        ChatAskReportSelectableCard(isSelected: isSelected, onTap: onTap) {
            ChatAskReportLeafContent(source: source, searchQuery: searchQuery, compact: true)
        }
    }
}

struct ChatAskReportLeafCard: View {
    let source: ChatSelectableHealthSource
    let isSelected: Bool
    let searchQuery: String
    let onTap: () -> Void

    var body: some View {
        ChatAskReportSelectableCard(isSelected: isSelected, onTap: onTap) {
            ChatAskReportLeafContent(source: source, searchQuery: searchQuery, compact: false)
        }
    }
}

struct ChatAskReportLeafContent: View {
    let source: ChatSelectableHealthSource
    let searchQuery: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            highlightedText(source.title, query: searchQuery)
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
            if let subtitle = source.subtitle, subtitle.isEmpty == false {
                highlightedText(subtitle, query: searchQuery)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
            }
            if let summary = source.summary, summary.isEmpty == false, compact == false {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if source.badges.isEmpty == false {
                ChatAskReportBadgeRow(badges: source.badges)
            }
            Text(L10n.text(source.resourceType.localizationKey))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct ChatAskReportBadgeRow: View {
    let badges: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }
            }
        }
    }
}

enum ChatAskReportRelatedCountFormatter {
    static func format(_ source: ChatSelectableHealthSource) -> String? {
        guard source.isMedicalCaseGroup, source.children.isEmpty == false else { return nil }
        let reports = source.children.filter { $0.resourceType == .examinationReport }.count
        let prescriptions = source.children.filter { $0.resourceType == .prescription }.count
        let plans = source.children.filter { $0.resourceType == .medicationPlan }.count
        let symptoms = source.children.filter { $0.resourceType == .symptom }.count
        let visits = source.children.filter { $0.resourceType == .visit }.count
        let surgeries = source.children.filter { $0.resourceType == .surgery }.count
        let followUps = source.children.filter { $0.resourceType == .followUp }.count
        var parts: [String] = []
        if reports > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.reports_format"), reports))
        }
        if prescriptions > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.prescriptions_format"), prescriptions))
        }
        if plans > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.plans_format"), plans))
        }
        if symptoms > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.symptoms_format"), symptoms))
        }
        if visits > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.visits_format"), visits))
        }
        if surgeries > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.surgeries_format"), surgeries))
        }
        if followUps > 0 {
            parts.append(String(format: L10n.text("chat.ask_report.sheet.count.follow_ups_format"), followUps))
        }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Search highlight

@ViewBuilder
func highlightedText(_ text: String, query: String) -> some View {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedQuery.isEmpty {
        Text(text)
    } else if let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) {
        let before = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let after = String(text[range.upperBound...])
        (
            Text(before)
            + Text(match).foregroundColor(.accentColor).fontWeight(.semibold)
            + Text(after)
        )
    } else {
        Text(text)
    }
}
