import Foundation

protocol DeepTutorMemberToolDataSource: Sendable {
    func members() async -> [Member]
}

