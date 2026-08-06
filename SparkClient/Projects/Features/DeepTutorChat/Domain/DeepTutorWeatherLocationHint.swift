import Foundation

nonisolated enum DeepTutorWeatherLocationHint {
    private nonisolated static let knownCities = [
        "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "武汉", "南京", "西安",
        "天津", "苏州", "长沙", "郑州", "青岛", "大连", "厦门", "昆明", "哈尔滨", "沈阳",
        "济南", "福州", "合肥", "石家庄", "长春", "南昌", "贵阳", "太原", "南宁", "乌鲁木齐",
        "兰州", "银川", "西宁", "海口", "拉萨", "呼和浩特", "香港", "澳门", "台北",
        "beijing", "shanghai", "guangzhou", "shenzhen", "hangzhou", "chengdu", "chongqing",
        "wuhan", "nanjing", "xian", "xi'an", "tianjin", "suzhou", "changsha", "zhengzhou",
        "qingdao", "dalian", "xiamen", "kunming", "harbin", "shenyang", "jinan", "fuzhou",
        "hefei", "shijiazhuang", "changchun", "nanchang", "guiyang", "taiyuan", "nanning",
        "hong kong", "macau", "taipei", "tokyo", "osaka", "seoul", "singapore", "london",
        "paris", "new york", "san francisco", "los angeles", "sydney", "melbourne"
    ]

    nonisolated static func hasExplicitCity(in input: String) -> Bool {
        extractCityName(from: input) != nil
    }

    nonisolated static func extractCityName(from input: String) -> String? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return nil }
        let lower = normalized.lowercased()

        for city in knownCities.sorted(by: { $0.count > $1.count }) {
            if lower.contains(city.lowercased()) {
                return city
            }
        }

        if let match = firstMatch(in: normalized, pattern: #"([\p{Han}]{2,8})市"#) {
            return match[1]
        }
        if let match = firstMatch(in: normalized, pattern: #"(?i)in\s+([a-z][a-z\s'-]{1,30})"#) {
            return match[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private nonisolated static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var parts: [String] = []
        for index in 0..<match.numberOfRanges {
            guard let subRange = Range(match.range(at: index), in: text) else { return nil }
            parts.append(String(text[subRange]))
        }
        return parts
    }
}
