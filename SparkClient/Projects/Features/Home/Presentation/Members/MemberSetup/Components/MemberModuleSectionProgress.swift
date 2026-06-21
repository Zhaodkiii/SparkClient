import Foundation

enum MemberModuleSectionStatus: String, Codable, Sendable, Equatable {
    case notStarted
    case incomplete
    case completed

    var displayTitle: String {
        switch self {
        case .notStarted: return "未开始"
        case .incomplete: return "未完成"
        case .completed: return "已完成"
        }
    }
}

struct MemberModuleSectionProgress: Identifiable, Equatable, Sendable {
    let module: MemberSetupModule
    let sectionCode: String
    let title: String
    let subtitle: String
    let iconName: String
    var summary: String
    var status: MemberModuleSectionStatus

    var id: String { "\(module.rawValue).\(sectionCode)" }
}

struct MemberModuleSectionProgressRecord: Codable, Equatable, Sendable {
    let sectionCode: String
    var summary: String
    var status: MemberModuleSectionStatus
}

enum MemberModuleSectionProgressCodec {
    static let extraKey = "section_progress"

    static func decode(from extra: [String: String]?) -> [String: MemberModuleSectionProgressRecord] {
        guard let extra, let json = extra[extraKey], json.isEmpty == false,
              let data = json.data(using: .utf8) else {
            return [:]
        }
        if let map = try? JSONDecoder().decode([String: MemberModuleSectionProgressRecord].self, from: data) {
            return map
        }
        if let list = try? JSONDecoder().decode([MemberModuleSectionProgressRecord].self, from: data) {
            return Dictionary(uniqueKeysWithValues: list.map { ($0.sectionCode, $0) })
        }
        return [:]
    }

    static func encode(_ records: [String: MemberModuleSectionProgressRecord]) -> String {
        guard records.isEmpty == false else { return "{}" }
        guard let data = try? JSONEncoder().encode(records),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
