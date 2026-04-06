import Combine
import Foundation

@MainActor
final class PatientContextStore: ObservableObject {
    @Published private(set) var context = PatientContext(members: [], selectedMemberID: nil)

    func update(members: [Member], selectedMemberID: Int?) {
        context = PatientContext(members: members, selectedMemberID: selectedMemberID)
    }

    func select(memberID: Int?) {
        context = PatientContext(members: context.members, selectedMemberID: memberID)
    }
}

