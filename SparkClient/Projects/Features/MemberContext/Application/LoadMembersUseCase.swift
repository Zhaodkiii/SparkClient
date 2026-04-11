import Foundation

struct LoadMembersUseCase: Sendable {
    let repository: any MembersRepository

    func execute() async -> [Member] {
        await repository.loadMembers()
    }
}
