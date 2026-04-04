import Foundation

struct SelectPatientUseCase: Sendable {
    func execute(members: [Member], selectedID: UUID?) -> UUID? {
        guard members.isEmpty == false else { return nil }
        if let selectedID, members.contains(where: { $0.id == selectedID }) {
            return selectedID
        }
        return members.first?.id
    }
}
