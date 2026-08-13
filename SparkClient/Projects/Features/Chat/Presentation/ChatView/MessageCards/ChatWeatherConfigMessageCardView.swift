import SwiftUI

struct ChatWeatherConfigMessageCardView: View {
    let payload: ChatWeatherConfigCardPayload
    let onOpen: (ChatWeatherConfigCardPayload) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cloud.sun.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WeatherConfigCardPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(WeatherConfigCardPalette.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("天气工具配置")
                        .font(.system(size: 12))
                        .foregroundStyle(WeatherConfigCardPalette.mutedText)
                }
            }

            Text(payload.message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            HStack {
                Spacer(minLength: 0)
                Button(payload.actionTitle) {
                    onOpen(payload)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(WeatherConfigCardPalette.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WeatherConfigCardPalette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .padding(.top, 8)
    }
}

private enum WeatherConfigCardPalette {
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let mutedText = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let border = Color.black.opacity(0.06)
}
