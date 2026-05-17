import SwiftUI

/// 医疗检查分类：用于列表筛选与分组展示。
enum ExaminationReportCategory: String, CaseIterable, Identifiable, Hashable {
    case laboratory
    case imaging
    case pathology

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .laboratory:
            return "home.medical.list.examination.category.laboratory"
        case .imaging:
            return "home.medical.list.examination.category.imaging"
        case .pathology:
            return "home.medical.list.examination.category.pathology"
        }
    }

    var icon: String {
        switch self {
        case .laboratory:
            return "testtube.2"
        case .imaging:
            return "camera.fill"
        case .pathology:
            return "doc.text.magnifyingglass"
        }
    }

    var color: Color {
        switch self {
        case .laboratory:
            return Color(uiColor: .systemBlue)
        case .imaging:
            return Color(uiColor: .systemIndigo)
        case .pathology:
            return Color(uiColor: .systemOrange)
        }
    }

    static func from(_ value: String?) -> ExaminationReportCategory {
        category(fromText: [value])
    }

    static func category(for report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> ExaminationReportCategory {
        category(fromText: [
            report.category,
            report.subCategory,
            report.itemName,
            report.findings,
            report.impression,
            report.extra?["summary"],
            report.extra?["abstract"]
        ])
    }

    /// 分类规则：
    /// 1. 优先按后端 `category` / `subCategory` 的标准值匹配；
    /// 2. 匹配不上时，再根据摘要字段做轻量分类；
    /// 3. 最终兜底归为实验室检查。
    func matches(_ report: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments) -> Bool {
        Self.category(for: report) == self
    }

    private static func directCategory(from values: [String?]) -> ExaminationReportCategory? {
        let candidates = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for candidate in candidates {
            switch candidate {
            case "laboratory", "lab", "实验室检查", "检验", "化验":
                return .laboratory
            case "imaging", "image", "影像", "影像学检查":
                return .imaging
            case "pathology", "病理", "病理检查":
                return .pathology
            default:
                continue
            }
        }

        return nil
    }

    private static func category(fromText values: [String?]) -> ExaminationReportCategory {
        if let direct = directCategory(from: values) {
            return direct
        }

        let haystack = values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        if ["影像", "超声", "ct", "mr", "mri", "放射", "x线", "b超", "彩超", "image"].contains(where: { haystack.contains($0) }) {
            return .imaging
        }
        if haystack.contains("病理") || haystack.contains("pathology") || haystack.contains("path") {
            return .pathology
        }
        return .laboratory
    }

}
