import SwiftUI

// MARK: - Attribution caption

/// Brief disclosure that metrics were read from the device Health app via HealthKit.
struct HealthKitDataSourceAttribution: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "heart.text.square.fill")
                .font(.caption2)
                .foregroundStyle(.pink)
                .accessibilityHidden(true)
            Text(L10n.text(
                "chat.healthkit.data_source.attribution",
                fallback: "Data is from the Health app on your iPhone (read via Apple HealthKit)."
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
