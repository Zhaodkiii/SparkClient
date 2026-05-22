import Foundation

/// 从 `list_member_health_sources` 工具参数解析 `resource_type` / `resource_types`。
enum HealthResourceListTypeFilter: Sendable {
    struct Parsed: Equatable, Sendable {
        let resourceTypes: [String]?
        let unrecognized: [String]
    }

    static func parse(arguments: [String: String]) -> Parsed {
        var raw = parseStringList(arguments["resource_types"])
        if let single = arguments["resource_type"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           single.isEmpty == false,
           raw.contains(single) == false {
            raw.append(single)
        }
        guard raw.isEmpty == false else {
            return Parsed(resourceTypes: nil, unrecognized: [])
        }
        var recognized: [String] = []
        var unrecognized: [String] = []
        for value in raw {
            if HealthResourceType(rawValue: value) != nil {
                if recognized.contains(value) == false {
                    recognized.append(value)
                }
            } else {
                unrecognized.append(value)
            }
        }
        return Parsed(
            resourceTypes: recognized.isEmpty ? nil : recognized,
            unrecognized: unrecognized
        )
    }

    private static func parseStringList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return array
        }
        return trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}
