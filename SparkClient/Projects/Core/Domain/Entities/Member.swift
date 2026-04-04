import Foundation

struct Member: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var remoteID: Int?
    var name: String
    var age: Int
    var gender: String
    var relationship: String
    var avatar: String
    var birthDate: Date?
    var isPrimary: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        remoteID: Int? = nil,
        name: String,
        age: Int = 0,
        gender: String = "unknown",
        relationship: String = "self",
        avatar: String = "",
        birthDate: Date? = nil,
        isPrimary: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.remoteID = remoteID
        self.name = name
        self.age = age
        self.gender = gender
        self.relationship = relationship
        self.avatar = avatar
        self.birthDate = birthDate
        self.isPrimary = isPrimary
        self.updatedAt = updatedAt
    }
}
