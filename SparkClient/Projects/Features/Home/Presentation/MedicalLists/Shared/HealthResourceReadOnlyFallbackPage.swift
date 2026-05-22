import SwiftUI

/// 无独立 Home 详情页时的统一只读展示（症状/就诊/手术/随访/服药记录等）。
struct HealthResourceReadOnlyFallbackPage: View {
    let snapshot: HealthResourceReadOnlySnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if snapshot.fields.isEmpty {
                    Text(L10n.text("chat.ask_report.detail.fallback.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(snapshot.fields, id: \.title) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 88, alignment: .leading)
                                Text(row.value)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
                if let body = snapshot.bodyText, body.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("chat.ask_report.detail.fallback.notes"))
                            .font(.headline)
                        Text(body)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(snapshot.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.typeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(snapshot.navigationTitle)
                .font(.title3.weight(.semibold))
            if let subtitle = snapshot.subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthResourceReadOnlySnapshot: Equatable, Sendable {
    let typeLabel: String
    let navigationTitle: String
    let subtitle: String?
    let fields: [HealthResourceReadOnlyField]
    let bodyText: String?
}

struct HealthResourceReadOnlyField: Equatable, Sendable {
    let title: String
    let value: String
}
