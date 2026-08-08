import Foundation

nonisolated struct DeepTutorBoundMemberDisplayModel: Equatable, Sendable {
    nonisolated enum State: Equatable, Sendable {
        case unbound
        case bound(memberID: Int, title: String, subtitle: String?)
        case missing(memberID: Int)
    }

    let state: State
    let iconName: String
    let title: String
    let accessibilityLabel: String

    nonisolated static func unbound() -> DeepTutorBoundMemberDisplayModel {
        DeepTutorBoundMemberDisplayModel(
            state: .unbound,
            iconName: "person.crop.circle.badge.plus",
            title: "选择成员",
            accessibilityLabel: "当前会话未绑定成员，双击选择成员"
        )
    }

    nonisolated static func bound(memberID: Int, title: String, subtitle: String?) -> DeepTutorBoundMemberDisplayModel {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "成员 #\(memberID)" : trimmedTitle
        let subtitleText = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessibility = [displayTitle, subtitleText].compactMap { $0 }.joined(separator: "，")
        return DeepTutorBoundMemberDisplayModel(
            state: .bound(memberID: memberID, title: displayTitle, subtitle: subtitleText?.isEmpty == false ? subtitleText : nil),
            iconName: "person.crop.circle.fill",
            title: displayTitle,
            accessibilityLabel: "当前会话成员：\(accessibility)"
        )
    }

    nonisolated static func missing(memberID: Int) -> DeepTutorBoundMemberDisplayModel {
        DeepTutorBoundMemberDisplayModel(
            state: .missing(memberID: memberID),
            iconName: "person.crop.circle.badge.exclamationmark",
            title: "成员失效",
            accessibilityLabel: "当前会话绑定成员已失效，请重新选择"
        )
    }
}
