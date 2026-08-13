import SwiftUI

struct WeatherResultCardDay: Identifiable, Equatable {
    let id: Int
    let date: Date
}

struct WeatherResultCardView: View {
    let result: WeatherResult
    var selectedDayID: Int?
    var days: [WeatherResultCardDay]
    var onSelectDay: ((Int) -> Void)?
    var showsHeader: Bool
    var wrapsInCard: Bool

    init(
        result: WeatherResult,
        selectedDayID: Int? = nil,
        days: [WeatherResultCardDay] = [],
        showsHeader: Bool = true,
        wrapsInCard: Bool = true,
        onSelectDay: ((Int) -> Void)? = nil
    ) {
        self.result = result
        self.selectedDayID = selectedDayID
        self.days = days
        self.showsHeader = showsHeader
        self.wrapsInCard = wrapsInCard
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        content
            .modifier(WeatherResultCardContainerModifier(enabled: wrapsInCard))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsHeader {
                header
            }

            if days.isEmpty == false {
                daySelector
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(temperatureText)
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .foregroundStyle(WeatherResultCardPalette.primaryText)

                    Text(result.condition)
                        .font(.body.weight(.medium))
                        .foregroundStyle(WeatherResultCardPalette.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        metricText(title: "H", value: highTemperatureText)
                        metricText(title: "L", value: lowTemperatureText)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: symbolName(for: result.condition))
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(symbolColor(for: result.condition))
                    .frame(width: 62, height: 62)
                    .padding(.top, 8)
            }

            VStack(spacing: 10) {
                metricRow(icon: "wind", title: L10n.text("ai_settings.weather.preview.wind", fallback: "风速"), value: windText)
                metricRow(icon: "drop.fill", title: L10n.text("ai_settings.weather.preview.humidity", fallback: "湿度"), value: humidityText)
                metricRow(icon: "cloud.rain.fill", title: L10n.text("ai_settings.weather.preview.precipitation", fallback: "降水概率"), value: precipitationText)
            }

            sourceFooter
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WeatherResultCardPalette.accent)
                .frame(width: 34, height: 34)
                .background(WeatherResultCardPalette.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("ai_settings.weather.preview.title", fallback: "天气预览"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeatherResultCardPalette.primaryText)
                Text(result.locationName)
                    .font(.caption)
                    .foregroundStyle(WeatherResultCardPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days) { day in
                    Button {
                        onSelectDay?(day.id)
                    } label: {
                        VStack(spacing: 8) {
                            Text(day.date.weatherResultCardDayNumber)
                                .font(.system(size: 15, weight: .semibold))
                            Text(day.date.weatherResultCardWeekday)
                                .font(.system(size: 13, weight: .medium))
                            Circle()
                                .fill(selectedDayID == day.id ? .white : WeatherResultCardPalette.secondaryText.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .opacity(day.id == 0 ? 1 : 0.35)
                        }
                        .foregroundStyle(selectedDayID == day.id ? .white : WeatherResultCardPalette.secondaryText)
                        .frame(width: 46, height: 78)
                        .background(
                            Capsule()
                                .fill(selectedDayID == day.id ? WeatherResultCardPalette.primaryText : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelectDay == nil)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func metricText(title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text("\(title):")
                .foregroundStyle(WeatherResultCardPalette.secondaryText)
            Text(value)
                .foregroundStyle(WeatherResultCardPalette.primaryText)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func metricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WeatherResultCardPalette.accent)
                .frame(width: 20)
            Text(title)
                .font(.footnote)
                .foregroundStyle(WeatherResultCardPalette.secondaryText)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeatherResultCardPalette.primaryText)
        }
        .padding(.vertical, 2)
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if provider == .weatherKit {
                HStack(spacing: 10) {
                    appleWeatherBrandBadge

                    if let url = appleWeatherLegalURL {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(L10n.text("ai_settings.weather.preview.apple_legal_attribution", fallback: "Legal Attribution"))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(WeatherResultCardPalette.link)
                    }

                    Spacer()
                }
            } else {
                Text(L10n.format("ai_settings.weather.preview.source_format", fallback: "Weather data: %@", sourceName))
                    .font(.caption2)
                    .foregroundStyle(WeatherResultCardPalette.secondaryText)
            }
        }
        .padding(.top, 2)
    }

    private var appleWeatherBrandBadge: some View {
        HStack(spacing: 8) {
            Image("applogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text(sourceName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WeatherResultCardPalette.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(WeatherResultCardPalette.brandBackground)
        )
        .overlay(
            Capsule()
                .stroke(WeatherResultCardPalette.brandStroke, lineWidth: 1)
        )
    }

    private var appleWeatherLegalURL: URL? {
        if let url = result.legalPageURL {
            return url
        }
        return URL(string: "https://weatherkit.apple.com/legal-attribution.html")
    }

    private var provider: WeatherProviderID? {
        WeatherProviderID.parse(company: result.providerName)
    }

    private var sourceName: String {
        switch provider {
        case .openWeather:
            return "OpenWeather"
        case .qWeather:
            return "QWeather"
        case .weatherKit:
            return "Apple Weather"
        case nil:
            return result.providerName
        }
    }

    private var temperatureText: String {
        result.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "--°C"
    }

    private var highTemperatureText: String {
        result.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "--"
    }

    private var lowTemperatureText: String {
        result.feelsLikeC.map { "\(Int($0.rounded()))°C" } ?? "--"
    }

    private var windText: String {
        result.windSpeedMS.map { String(format: "%.1f m/s", $0) } ?? "--"
    }

    private var humidityText: String {
        result.humidityPercent.map { "\($0)%" } ?? "--"
    }

    private var precipitationText: String {
        result.precipitationProbabilityPercent.map { "\($0)%" } ?? "--"
    }

    private func symbolName(for condition: String) -> String {
        let text = condition.lowercased()
        if text.contains("rain") || text.contains("雨") { return "cloud.rain.fill" }
        if text.contains("snow") || text.contains("雪") { return "snowflake" }
        if text.contains("cloud") || text.contains("云") || text.contains("阴") { return "cloud.fill" }
        if text.contains("storm") || text.contains("雷") { return "cloud.bolt.rain.fill" }
        if text.contains("fog") || text.contains("雾") { return "cloud.fog.fill" }
        return "sun.max.fill"
    }

    private func symbolColor(for condition: String) -> Color {
        let text = condition.lowercased()
        if text.contains("rain") || text.contains("雨") { return Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255) }
        if text.contains("snow") || text.contains("雪") { return Color(red: 98 / 255, green: 166 / 255, blue: 235 / 255) }
        if text.contains("cloud") || text.contains("云") || text.contains("阴") { return Color(red: 132 / 255, green: 142 / 255, blue: 152 / 255) }
        if text.contains("storm") || text.contains("雷") { return Color(red: 245 / 255, green: 190 / 255, blue: 66 / 255) }
        return Color(red: 246 / 255, green: 174 / 255, blue: 45 / 255)
    }
}

private enum WeatherResultCardPalette {
    static let card = Color.white
    static let primaryText = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    static let secondaryText = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let link = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    static let brandBackground = Color(red: 246 / 255, green: 247 / 255, blue: 249 / 255)
    static let brandStroke = Color.black.opacity(0.06)
}

private struct WeatherResultCardContainerModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(18)
                .background(WeatherResultCardPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        } else {
            content
        }
    }
}

private extension Date {
    var weatherResultCardDayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter.string(from: self)
    }

    var weatherResultCardWeekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}
