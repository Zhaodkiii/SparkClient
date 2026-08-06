import Foundation

enum WeatherProviderID: String, Codable, Sendable, CaseIterable {
    case openWeather = "OPENWEATHER"
    case qWeather = "QWEATHER"
    case weatherKit = "WEATHERKIT"

    nonisolated static let locallyAdapted: Set<WeatherProviderID> = [
        .openWeather,
        .qWeather,
        .weatherKit
    ]

    nonisolated static func parse(company: String) -> WeatherProviderID? {
        let normalized = company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.isEmpty == false else { return nil }
        switch normalized {
        case "OPENWEATHER":
            return .openWeather
        case "QWEATHER", "QWEATHER_KEY":
            return .qWeather
        case "WEATHERKIT", "APPLEWEATHER", "APPLE_WEATHER":
            return .weatherKit
        default:
            return WeatherProviderID(rawValue: normalized)
        }
    }

    nonisolated var hasLocalAdapter: Bool {
        switch self {
        case .openWeather:
            return true
        case .weatherKit:
            if #available(iOS 16.0, *) {
                return true
            }
            return false
        case .qWeather:
            return true
        }
    }

    /// 已在设置页展示但尚未接入本地适配器的供应商。
    nonisolated var isReserved: Bool {
        hasLocalAdapter == false
    }

    nonisolated var usesAPIKey: Bool {
        switch self {
        case .openWeather, .qWeather:
            return true
        case .weatherKit:
            return false
        }
    }
}

/// 对齐 HealthClient：requestURL 可为完整 URL 或 host（如 `api.openweathermap.org`），空值走各供应商默认 host。
nonisolated enum WeatherEndpointNormalizer {
    nonisolated static func defaultBaseURL(for provider: WeatherProviderID) -> URL {
        switch provider {
        case .openWeather:
            return URL(string: "https://api.openweathermap.org")!
        case .qWeather:
            return URL(string: "https://devapi.qweather.com")!
        case .weatherKit:
            return URL(string: "https://weatherkit.apple.com")!
        }
    }

    nonisolated static func normalizedBaseURL(requestURL: String, provider: WeatherProviderID) -> URL {
        let trimmed = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return defaultBaseURL(for: provider)
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let url = URL(string: trimmed) {
                return url
            }
        } else {
            if let url = URL(string: "https://\(trimmed)") {
                return url
            }
        }
        return defaultBaseURL(for: provider)
    }

    nonisolated static func isValidEndpoint(requestURL: String, provider: WeatherProviderID) -> Bool {
        let trimmed = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)?.host != nil
        }
        return trimmed.contains(".")
    }

    nonisolated static func normalizedTimeRange(_ timeRange: String) -> String {
        let normalized = timeRange.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "today", "现在", "当前":
            return "now"
        case "tomorrow", "明天":
            return "tomorrow"
        default:
            return normalized.isEmpty ? "now" : normalized
        }
    }
}

nonisolated struct WeatherRuntimeConfigRevision: Codable, Equatable, Sendable {
    nonisolated static let schemaVersion = 1

    var schemaVersion: Int
    var localRevision: Int
    var updatedAt: Date
    var activeWeatherKeyID: UUID?
    var preferencesHash: String

    init(
        schemaVersion: Int = WeatherRuntimeConfigRevision.schemaVersion,
        localRevision: Int = 1,
        updatedAt: Date = Date(),
        activeWeatherKeyID: UUID? = nil,
        preferencesHash: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.localRevision = localRevision
        self.updatedAt = updatedAt
        self.activeWeatherKeyID = activeWeatherKeyID
        self.preferencesHash = preferencesHash
    }
}

struct WeatherRuntimeConfig: Equatable, Sendable {
    var provider: WeatherProviderID
    var displayName: String
    var apiKey: String
    var requestURL: URL
    var revision: WeatherRuntimeConfigRevision
    var rawKeyID: UUID
}

struct WeatherQueryRequest: Sendable {
    var latitude: Double
    var longitude: Double
    var timeRange: String
    var locationName: String?
    var config: WeatherRuntimeConfig
}

struct GeocodeQueryRequest: Sendable {
    var keyword: String
    var config: WeatherRuntimeConfig
}

struct GeocodeResult: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var state: String?
}

struct WeatherResult: Codable, Equatable, Sendable {
    var providerName: String
    var locationName: String
    var latitude: Double
    var longitude: Double
    var timeRange: String
    var observedAt: Date?
    var temperatureC: Double?
    var feelsLikeC: Double?
    var condition: String
    var humidityPercent: Int?
    var windSpeedMS: Double?
    var windDirectionDeg: Int?
    var precipitationProbabilityPercent: Int?
    var revision: WeatherRuntimeConfigRevision

    var markdown: String {
        var lines: [String] = [
            "实时天气（\(providerName)，配置版本 \(revision.localRevision)）",
            "地点：\(locationName)",
            "坐标：\(String(format: "%.2f", latitude)), \(String(format: "%.2f", longitude))",
            "时间范围：\(timeRange)"
        ]
        if let observedAt {
            lines.append("观测时间：\(Self.formatter.string(from: observedAt))")
        }
        lines.append("天气：\(condition)")
        if let temperatureC {
            lines.append("温度：\(Self.formatNumber(temperatureC))°C")
        }
        if let feelsLikeC {
            lines.append("体感温度：\(Self.formatNumber(feelsLikeC))°C")
        }
        if let humidityPercent {
            lines.append("湿度：\(humidityPercent)%")
        }
        if let windSpeedMS {
            let windLine: String
            if let windDirectionDeg {
                windLine = "风向 \(windDirectionDeg)°，"
            } else {
                windLine = ""
            }
            lines.append("风力：\(windLine)风速 \(Self.formatNumber(windSpeedMS)) m/s")
        }
        if let precipitationProbabilityPercent {
            lines.append("降水概率：\(precipitationProbabilityPercent)%")
        }
        return lines.joined(separator: "\n")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

enum WeatherRuntimeError: LocalizedError {
    case disabled
    case missingActiveProvider
    case missingAPIKey(String)
    case invalidEndpoint(String)
    case unsupportedProvider(String)
    case missingCoordinates
    case emptyKeyword
    case locationNotFound(String)
    case forecastUnavailable(String)
    case badHTTPStatus(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "天气查询未启用，请在 AI 设置 -> 天气工具中打开“启用天气”。"
        case .missingActiveProvider:
            return "尚未配置可用的天气服务，请在 AI 设置中的天气工具里启用一个天气供应商。"
        case .missingAPIKey(let provider):
            return "\(provider) 尚未填写 API Key，请先在 AI 设置中的天气工具里补充密钥。"
        case .invalidEndpoint(let endpoint):
            return "天气服务 endpoint 无效：\(endpoint)"
        case .unsupportedProvider(let provider):
            return "当前天气供应商 \(provider) 还没有本地适配器。"
        case .missingCoordinates:
            return "天气查询缺少有效经纬度，请先通过 query_location 或 get_current_location 获取坐标。"
        case .emptyKeyword:
            return "地点关键词不能为空。"
        case .locationNotFound(let keyword):
            return "未找到地点“\(keyword)”的坐标，请让用户提供更明确的城市名称。"
        case .forecastUnavailable(let timeRange):
            return "当前天气供应商暂不支持时间范围“\(timeRange)”的查询，请改为 today 或 tomorrow。"
        case .badHTTPStatus(let status, let body):
            return "天气服务返回异常状态码 \(status)：\(body)"
        case .invalidResponse(let provider):
            return "\(provider) 返回的数据格式无法解析。"
        }
    }
}
