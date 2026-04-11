import Foundation

struct SelectMemberUseCase: Sendable {
    func execute(members: [Member], selectedID: Int?) -> Int? {
        guard members.isEmpty == false else { return nil }
        if let selectedID, members.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return members.first?.id
    }
}
