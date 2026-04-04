import Foundation

struct PatientContext: Equatable, Sendable {
    let members: [Member]
    let selectedMemberID: UUID?

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }
}

protocol PatientRepository: Sendable {
    func loadPatients() async -> [Member]
}
