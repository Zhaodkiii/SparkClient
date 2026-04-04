import Combine
import Foundation

@MainActor
final class PatientContextStore: ObservableObject {
    @Published private(set) var context = PatientContext(members: [], selectedMemberID: nil)

    func update(members: [Member], selectedMemberID: UUID?) {
        context = PatientContext(members: members, selectedMemberID: selectedMemberID)
    }

    func select(memberID: UUID?) {
        context = PatientContext(members: context.members, selectedMemberID: memberID)
    }
}

