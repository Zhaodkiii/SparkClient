import Foundation

struct MemberContext: Equatable, Sendable {
    let members: [Member]
    let selectedMemberID: Int?

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }
}

protocol MembersRepository: Sendable {
    func loadMembers() async -> [Member]
}
