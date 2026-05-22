import Foundation

/// 问报告 Sheet 时间轴统一行模型（与需求 §4 `ChatSelectableHealthSource` 对齐）。
struct ChatSelectableHealthSource: Identifiable, Equatable, Sendable {
    let id: String
    let resourceType: HealthResourceType
    let resourceID: Int
    let memberID: Int
    let occurredAt: Date?
    let title: String
    let subtitle: String?
    let summary: String?
    let badges: [String]
    let searchText: String
    let medicalCaseID: Int?
    let attachmentCount: Int?
    /// 病历聚合卡下的子资料（仅 `medical_case` 父节点使用）。
    let children: [ChatSelectableHealthSource]

    var selectionKey: String { id }

    var isMedicalCaseGroup: Bool {
        resourceType == .medicalCase && children.isEmpty == false
    }

    func replacingChildren(_ children: [ChatSelectableHealthSource]) -> ChatSelectableHealthSource {
        ChatSelectableHealthSource(
            id: id,
            resourceType: resourceType,
            resourceID: resourceID,
            memberID: memberID,
            occurredAt: occurredAt,
            title: title,
            subtitle: subtitle,
            summary: summary,
            badges: badges,
            searchText: searchText,
            medicalCaseID: medicalCaseID,
            attachmentCount: attachmentCount,
            children: children
        )
    }

}

/// 时间轴一行：病历聚合组或独立可选资料。
enum AskReportTimelineRow: Identifiable, Equatable, Sendable {
    case medicalCaseGroup(ChatSelectableHealthSource)
    case leaf(ChatSelectableHealthSource)

    var id: String {
        switch self {
        case .medicalCaseGroup(let source): return "group:\(source.id)"
        case .leaf(let source): return "leaf:\(source.id)"
        }
    }

    var selectableSource: ChatSelectableHealthSource {
        switch self {
        case .medicalCaseGroup(let source), .leaf(let source):
            return source
        }
    }

    var occurredAt: Date? {
        selectableSource.occurredAt
    }
}

struct AskReportMappedTimeline: Equatable, Sendable {
    let allRows: [AskReportTimelineRow]
    let medicalCaseRows: [AskReportTimelineRow]
    let healthExamRows: [AskReportTimelineRow]
    let examinationRows: [AskReportTimelineRow]
    let medicationRows: [AskReportTimelineRow]
    let allSelectableSources: [ChatSelectableHealthSource]

    func rows(for tab: AskReportTab) -> [AskReportTimelineRow] {
        switch tab {
        case .all: return allRows
        case .medicalCase: return medicalCaseRows
        case .healthExam: return healthExamRows
        case .examination: return examinationRows
        case .medication: return medicationRows
        }
    }
}

enum AskReportTab: String, CaseIterable, Identifiable {
    case all
    case medicalCase
    case healthExam
    case examination
    case medication

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .all: return "chat.ask_report.sheet.tab.all"
        case .medicalCase: return "chat.ask_report.sheet.tab.medical_case"
        case .healthExam: return "chat.ask_report.sheet.tab.health_exam"
        case .examination: return "chat.ask_report.sheet.tab.examination"
        case .medication: return "chat.ask_report.sheet.tab.medication"
        }
    }

    func matches(_ type: HealthResourceType) -> Bool {
        switch self {
        case .all: return true
        case .medicalCase: return type == .medicalCase
        case .healthExam: return type == .healthExamReport
        case .examination: return type == .examinationReport
        case .medication:
            switch type {
            case .medicineBox, .prescription, .medicationPlan, .medicationRecord, .medicationSummary:
                return true
            default:
                return false
            }
        }
    }
}
