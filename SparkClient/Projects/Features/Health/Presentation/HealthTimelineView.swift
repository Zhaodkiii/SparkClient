import SwiftUI

struct HealthTimelineView: View {
    @ObservedObject var viewModel: HealthTimelineViewModel
    let session: UserSession

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayName)
                        .font(.headline)
                    Text(L10n.text("health.intro"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if viewModel.metrics.isEmpty && viewModel.isLoading {
                ProgressView(L10n.text("health.loading"))
            } else {
                ForEach(viewModel.metrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.metricTitle(metric.type))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(displayValue(metric))
                                .font(.body.weight(.medium))
                        }

                        Text(metric.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(L10n.text("health.title"))
        .task {
            await viewModel.load()
        }
        .overlay(alignment: .center) {
            if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(L10n.text("common.load_failed"))
                        .font(.headline)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func displayValue(_ metric: HealthMetric) -> String {
        switch metric.type {
        case .steps:
            return "\(Int(metric.value)) \(metric.unit)"
        default:
            return String(format: "%.1f %@", metric.value, metric.unit)
        }
    }
}
