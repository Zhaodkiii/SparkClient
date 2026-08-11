import CoreLocation
import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

private enum AIWeatherPreviewState: Equatable {
    case idle
    case disabled
    case missingProvider
    case needsLocationPermission
    case locationDenied
    case loadingLocation
    case loadingWeather
    case loaded(AIWeatherPreviewModel)
    case failed(String)
}

private struct AIWeatherPreviewModel: Equatable {
    var provider: WeatherProviderID
    var providerName: String
    var sourceName: String
    var locationName: String
    var observedAt: Date?
    var temperatureC: Double?
    var feelsLikeC: Double?
    var condition: String
    var highTemperatureC: Double?
    var lowTemperatureC: Double?
    var humidityPercent: Int?
    var windSpeedMS: Double?
    var precipitationProbabilityPercent: Int?
    var revision: WeatherRuntimeConfigRevision
}

private struct AIWeatherPreviewDay: Identifiable, Equatable {
    let id: Int
    let date: Date

    var queryTimeRange: String {
        switch id {
        case 0:
            return "now"
        case 1:
            return "tomorrow"
        case 2...6:
            return "7d"
        default:
            return "now"
        }
    }
}

@MainActor
private final class AIWeatherPreviewViewModel: ObservableObject {
    @Published private(set) var state: AIWeatherPreviewState = .idle
    @Published var selectedDayID: Int = 0

    let days: [AIWeatherPreviewDay] = AIWeatherPreviewDay.makeNextSevenDays()

    private let gateway: WeatherGateway
    private let logger: Logger
    private var currentSnapshot: AISettingsSnapshot?
    private var loadTask: Task<Void, Never>?
    private var lastCoordinate: (latitude: Double, longitude: Double)?

    init(gateway: WeatherGateway = WeatherGateway(), logger: Logger = ConsoleLogger()) {
        self.gateway = gateway
        self.logger = logger
    }

    deinit {
        loadTask?.cancel()
    }

    func refresh(snapshot: AISettingsSnapshot) {
        currentSnapshot = snapshot
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(snapshot: snapshot, forceLocationRefresh: false)
        }
    }

    func retry() {
        guard let currentSnapshot else { return }
        refresh(snapshot: currentSnapshot)
    }

    func reloadSelectedDay() {
        guard let currentSnapshot else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(snapshot: currentSnapshot, forceLocationRefresh: false)
        }
    }

    func requestLocationPermission(snapshot: AISettingsSnapshot) {
        currentSnapshot = snapshot
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let status = await SparkLocationService.requestWhenInUseAuthorization()
            guard Task.isCancelled == false else { return }
            await self?.handleAuthorizationResult(status, snapshot: snapshot)
        }
    }

    func recheckLocationPermission(snapshot: AISettingsSnapshot) {
        currentSnapshot = snapshot
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.load(snapshot: snapshot, forceLocationRefresh: true)
        }
    }

    private func load(snapshot: AISettingsSnapshot, forceLocationRefresh: Bool) async {
        currentSnapshot = snapshot

        guard snapshot.weatherToolPreferences.useWeather else {
            state = .disabled
            return
        }

        let config: WeatherRuntimeConfig
        do {
            config = try WeatherRuntimeConfigResolver.resolve(from: snapshot)
        } catch WeatherRuntimeError.disabled {
            state = .disabled
            return
        } catch WeatherRuntimeError.missingActiveProvider {
            state = .missingProvider
            return
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let status = SparkLocationService.authorizationStatus()
        switch status {
        case .notDetermined:
            state = .needsLocationPermission
            return
        case .denied, .restricted:
            state = .locationDenied
            return
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            state = .locationDenied
            return
        }

        let coordinate: (latitude: Double, longitude: Double)
        if let lastCoordinate, forceLocationRefresh == false {
            coordinate = lastCoordinate
        } else {
            state = .loadingLocation
            do {
                coordinate = try await SparkLocationService.currentCoordinate()
                lastCoordinate = coordinate
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
        }

        state = .loadingWeather
        await queryWeather(config: config, coordinate: coordinate)
    }

    private func handleAuthorizationResult(_ status: CLAuthorizationStatus, snapshot: AISettingsSnapshot) async {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            await load(snapshot: snapshot, forceLocationRefresh: true)
        case .notDetermined:
            state = .needsLocationPermission
        default:
            state = .locationDenied
        }
    }

    private func queryWeather(
        config: WeatherRuntimeConfig,
        coordinate: (latitude: Double, longitude: Double)
    ) async {
        let day = days.first(where: { $0.id == selectedDayID }) ?? days[0]
        logAppleWeather(config: config, result: "start", coordinate: coordinate, timeRange: day.queryTimeRange)

        do {
            let result = try await gateway.queryWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeRange: day.queryTimeRange,
                locationName: L10n.text("ai_settings.weather.preview.current_location", fallback: "当前位置"),
                config: config
            )
            guard Task.isCancelled == false else { return }
            state = .loaded(AIWeatherPreviewModel(result: result, provider: config.provider, selectedDayID: selectedDayID))
            logAppleWeather(config: config, result: "success", coordinate: coordinate, timeRange: day.queryTimeRange)
        } catch {
            guard Task.isCancelled == false else { return }
            state = .failed(error.localizedDescription)
            logAppleWeather(
                config: config,
                result: "failure",
                coordinate: coordinate,
                timeRange: day.queryTimeRange,
                errorCode: LogMessageSanitizer.singleLineSnippet(error.localizedDescription, limit: 80)
            )
        }
    }

    private func logAppleWeather(
        config: WeatherRuntimeConfig,
        result: String,
        coordinate: (latitude: Double, longitude: Double),
        timeRange: String,
        errorCode: String? = nil
    ) {
        guard config.provider == .weatherKit else { return }

        var message = [
            "event=ai_weather_preview.apple_weather.query",
            "provider=APPLEWEATHER",
            "source=Apple Weather",
            "result=\(result)",
            "timeRange=\(timeRange)",
            "locationPrecision=rounded",
            "latitude=\(String(format: "%.2f", coordinate.latitude))",
            "longitude=\(String(format: "%.2f", coordinate.longitude))",
            "revision=\(config.revision.localRevision)"
        ].joined(separator: " ")

        if let errorCode {
            message += " errorCode=\(errorCode)"
        }

        logger.info(message, module: .aiConfig)
    }
}

struct AIWeatherPreviewPanel: View {
    let snapshot: AISettingsSnapshot

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AIWeatherPreviewViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            switch viewModel.state {
            case .idle, .loadingLocation, .loadingWeather:
                loadingView
            case .disabled:
                emptyState(
                    icon: "cloud.slash",
                    title: L10n.text("ai_settings.weather.preview.disabled", fallback: "天气未启用"),
                    message: L10n.text("ai_settings.weather.preview.disabled_message", fallback: "开启天气并启用一个供应商后，可以在这里预览当前位置天气。")
                )
            case .missingProvider:
                emptyState(
                    icon: "cloud.badge.questionmark",
                    title: L10n.text("ai_settings.weather.preview.missing_provider", fallback: "请选择天气供应商"),
                    message: L10n.text("ai_settings.weather.preview.missing_provider_message", fallback: "启用 OpenWeather、QWeather 或 Apple Weather 后会自动刷新预览。")
                )
            case .needsLocationPermission:
                locationPermissionView(
                    title: L10n.text("ai_settings.weather.preview.location_permission_title", fallback: "允许位置权限"),
                    message: L10n.text("ai_settings.weather.preview.location_permission_message", fallback: "需要使用当前位置来预览实时天气。"),
                    buttonTitle: L10n.text("ai_settings.weather.preview.allow_location", fallback: "允许位置")
                ) {
                    viewModel.requestLocationPermission(snapshot: snapshot)
                }
            case .locationDenied:
                locationPermissionView(
                    title: L10n.text("ai_settings.weather.preview.location_unavailable_title", fallback: "无法获取位置"),
                    message: L10n.text("ai_settings.weather.preview.location_unavailable_message", fallback: "开启位置权限后，可以预览当前位置的实时天气和未来天气。")
                ) {
                    openAppSettings()
                }
            case .loaded(let model):
                loadedView(model)
            case .failed(let message):
                failedView(message)
            }
        }
        .padding(18)
        .background(AIWeatherPreviewPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        .task(id: taskID) {
            viewModel.refresh(snapshot: snapshot)
        }
        .onChange(of: viewModel.selectedDayID) {
            viewModel.reloadSelectedDay()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.recheckLocationPermission(snapshot: snapshot)
            }
        }
    }

    private var taskID: String {
        [
            "\(snapshot.weatherToolPreferences.useWeather)",
            "\(snapshot.weatherConfigRevision.localRevision)",
            snapshot.weatherConfigRevision.activeWeatherKeyID?.uuidString ?? "none"
        ].joined(separator: "|")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AIWeatherPreviewPalette.accent)
                .frame(width: 34, height: 34)
                .background(AIWeatherPreviewPalette.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("ai_settings.weather.preview.title", fallback: "天气预览"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AIWeatherPreviewPalette.primaryText)
                Text(L10n.text("ai_settings.weather.preview.subtitle", fallback: "当前位置实时天气"))
                    .font(.caption)
                    .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
            }

            Spacer()

            Button {
                viewModel.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AIWeatherPreviewPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(AIWeatherPreviewPalette.accent.opacity(0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel(L10n.text("ai_settings.weather.preview.retry", fallback: "重试"))
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(L10n.text("ai_settings.weather.preview.loading_weather", fallback: "正在获取当前位置天气"))
                .font(.footnote)
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
            Spacer()
        }
        .frame(minHeight: 96)
    }

    private func loadedView(_ model: AIWeatherPreviewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            daySelector

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.temperatureText)
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .foregroundStyle(AIWeatherPreviewPalette.primaryText)

                    Text(model.condition)
                        .font(.body.weight(.medium))
                        .foregroundStyle(AIWeatherPreviewPalette.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        metricText(title: "H", value: model.highTemperatureText)
                        metricText(title: "L", value: model.lowTemperatureText)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: symbolName(for: model.condition))
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(symbolColor(for: model.condition))
                    .frame(width: 62, height: 62)
                    .padding(.top, 8)
            }

            VStack(spacing: 10) {
                metricRow(icon: "wind", title: L10n.text("ai_settings.weather.preview.wind", fallback: "风速"), value: model.windText)
                metricRow(icon: "drop.fill", title: L10n.text("ai_settings.weather.preview.humidity", fallback: "湿度"), value: model.humidityText)
                metricRow(icon: "cloud.rain.fill", title: L10n.text("ai_settings.weather.preview.precipitation", fallback: "降水概率"), value: model.precipitationText)
            }

            sourceFooter(model)
        }
    }

    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.days) { day in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.92)) {
                            viewModel.selectedDayID = day.id
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(day.date.aiWeatherDayNumber)
                                .font(.system(size: 15, weight: .semibold))
                            Text(day.date.aiWeatherWeekday)
                                .font(.system(size: 13, weight: .medium))
                            Circle()
                                .fill(viewModel.selectedDayID == day.id ? .white : AIWeatherPreviewPalette.secondaryText.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .opacity(day.id == 0 ? 1 : 0.35)
                        }
                        .foregroundStyle(viewModel.selectedDayID == day.id ? .white : AIWeatherPreviewPalette.secondaryText)
                        .frame(width: 46, height: 78)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedDayID == day.id ? AIWeatherPreviewPalette.primaryText : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func metricText(title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text("\(title):")
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
            Text(value)
                .foregroundStyle(AIWeatherPreviewPalette.primaryText)
        }
        .font(.subheadline.weight(.semibold))
    }

    private func metricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AIWeatherPreviewPalette.accent)
                .frame(width: 20)
            Text(title)
                .font(.footnote)
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AIWeatherPreviewPalette.primaryText)
        }
        .padding(.vertical, 2)
    }

    private func sourceFooter(_ model: AIWeatherPreviewModel) -> some View {
        HStack(spacing: 8) {
            Text(L10n.format("ai_settings.weather.preview.source_format", fallback: "Weather data: %@", model.sourceName))
                .font(.caption2)
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)

            if model.provider == .weatherKit,
               let url = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                Link(L10n.text("ai_settings.weather.preview.apple_legal_attribution", fallback: "Legal Attribution"), destination: url)
                    .font(.caption2.weight(.semibold))
            }

            Spacer()
        }
        .padding(.top, 2)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AIWeatherPreviewPalette.primaryText)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AIWeatherPreviewPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func locationPermissionView(
        title: String,
        message: String,
        buttonTitle: String = L10n.text("ai_settings.weather.preview.open_settings", fallback: "去设置开启"),
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            emptyState(icon: "location.slash.circle.fill", title: title, message: message)
            HStack(spacing: 10) {
                Button(action: action) {
                    Label(buttonTitle, systemImage: "location.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(AIWeatherPreviewPalette.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.recheckLocationPermission(snapshot: snapshot)
                } label: {
                    Text(L10n.text("ai_settings.weather.preview.retry", fallback: "重试"))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(AIWeatherPreviewPalette.background)
                        .foregroundStyle(AIWeatherPreviewPalette.primaryText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            emptyState(
                icon: "exclamationmark.triangle.fill",
                title: L10n.text("ai_settings.weather.preview.failed", fallback: "天气预览失败"),
                message: message
            )
            Button {
                viewModel.retry()
            } label: {
                Label(L10n.text("ai_settings.weather.preview.retry", fallback: "重试"), systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(AIWeatherPreviewPalette.accent.opacity(0.12))
                    .foregroundStyle(AIWeatherPreviewPalette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
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

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

private enum AIWeatherPreviewPalette {
    static let background = Color(red: 244 / 255, green: 244 / 255, blue: 248 / 255)
    static let card = Color.white
    static let primaryText = Color(red: 11 / 255, green: 11 / 255, blue: 15 / 255)
    static let secondaryText = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
}

private extension AIWeatherPreviewDay {
    static func makeNextSevenDays(calendar: Calendar = .current, now: Date = Date()) -> [AIWeatherPreviewDay] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return AIWeatherPreviewDay(id: offset, date: date)
        }
    }
}

private extension AIWeatherPreviewModel {
    init(result: WeatherResult, provider: WeatherProviderID, selectedDayID: Int) {
        let isForecastDay = selectedDayID > 0
        self.provider = provider
        providerName = result.providerName
        sourceName = provider.previewSourceName
        locationName = result.locationName
        observedAt = result.observedAt
        temperatureC = result.temperatureC
        feelsLikeC = result.feelsLikeC
        condition = result.condition
        highTemperatureC = isForecastDay ? result.temperatureC : result.temperatureC
        lowTemperatureC = isForecastDay ? result.feelsLikeC : result.feelsLikeC
        humidityPercent = result.humidityPercent
        windSpeedMS = result.windSpeedMS
        precipitationProbabilityPercent = result.precipitationProbabilityPercent
        revision = result.revision
    }

    var temperatureText: String {
        temperatureC.map { "\(Int($0.rounded()))°C" } ?? "--°C"
    }

    var highTemperatureText: String {
        highTemperatureC.map { "\(Int($0.rounded()))°C" } ?? "--"
    }

    var lowTemperatureText: String {
        lowTemperatureC.map { "\(Int($0.rounded()))°C" } ?? "--"
    }

    var windText: String {
        windSpeedMS.map { String(format: "%.1f m/s", $0) } ?? "--"
    }

    var humidityText: String {
        humidityPercent.map { "\($0)%" } ?? "--"
    }

    var precipitationText: String {
        precipitationProbabilityPercent.map { "\($0)%" } ?? "--"
    }
}

private extension WeatherProviderID {
    var previewSourceName: String {
        switch self {
        case .openWeather:
            return "OpenWeather"
        case .qWeather:
            return "QWeather"
        case .weatherKit:
            return "Apple Weather"
        }
    }
}

private extension Date {
    var aiWeatherDayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter.string(from: self)
    }

    var aiWeatherWeekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: self)
    }
}
