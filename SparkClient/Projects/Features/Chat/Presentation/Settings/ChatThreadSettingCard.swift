import SwiftUI

struct ChatThreadSettingOption<Value: Hashable>: Identifiable, Equatable {
    let id: String
    let value: Value
    let title: String
    let detail: String?

    init(id: String, value: Value, title: String, detail: String? = nil) {
        self.id = id
        self.value = value
        self.title = title
        self.detail = detail
    }
}

struct ChatThreadSettingCard<Value: Hashable>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let options: [ChatThreadSettingOption<Value>]
    @Binding var selection: Value

    private var selectedIndex: Int {
        options.firstIndex(where: { $0.value == selection }) ?? 0
    }

    private var selectedOption: ChatThreadSettingOption<Value> {
        options[selectedIndex]
    }

    private var progress: CGFloat {
        let total = max(options.count - 1, 1)
        return CGFloat(selectedIndex) / CGFloat(total)
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            if let detail = selectedOption.detail, detail.isEmpty == false {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            circularMeter
                .padding(.vertical, 4)

            stepperRow
        }
        .padding(18)
        .background(backgroundShape)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.accentColor.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var circularMeter: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(progress, 0.015))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.accentColor.opacity(0.55),
                            Color.accentColor
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(selectedOption.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(L10n.text("chat.settings.current"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 116, height: 116)
        .frame(maxWidth: .infinity)
    }

    private var stepperRow: some View {
        HStack(spacing: 12) {
            Button {
                guard selectedIndex > 0 else { return }
                selection = options[selectedIndex - 1].value
            } label: {
                Image(systemName: "minus")
                    .font(.headline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(selectedIndex == 0 ? Color.secondary : Color.primary)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(selectedIndex == 0)

            VStack(spacing: 2) {
                Text(L10n.text("chat.settings.current"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedOption.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)

            Button {
                guard selectedIndex < options.count - 1 else { return }
                selection = options[selectedIndex + 1].value
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(selectedIndex >= options.count - 1 ? Color.secondary : Color.white)
                    .background(plusButtonBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(selectedIndex >= options.count - 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground).opacity(0.5), in: Capsule())
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.08),
                                Color(uiColor: .secondarySystemBackground).opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var plusButtonBackground: Color {
        selectedIndex >= options.count - 1 ? Color(uiColor: .tertiarySystemFill) : Color.accentColor
    }
}

struct ChatThreadToggleSettingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
            }
        }
        .padding(18)
        .background(backgroundShape)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.accentColor.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(uiColor: .systemBackground))
    }
}
