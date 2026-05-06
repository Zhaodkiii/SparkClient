import Foundation

struct UserSession: Codable, Equatable, Sendable {
    enum SignInMethod: String, Codable, Sendable {
        case apple
        case phone
    }

    let accountID: Int64
    let email: String
    let displayName: String
    let signedInAt: Date
    let signInMethod: SignInMethod
    let isPro: Bool
    let isNewUser: Bool

    init(
        accountID: Int64,
        email: String,
        displayName: String,
        signedInAt: Date,
        signInMethod: SignInMethod = .apple,
        isPro: Bool = false,
        isNewUser: Bool = false
    ) {
        self.accountID = accountID
        self.email = email
        self.displayName = displayName
        self.signedInAt = signedInAt
        self.signInMethod = signInMethod
        self.isPro = isPro
        self.isNewUser = isNewUser
    }

    enum CodingKeys: String, CodingKey {
        case accountID
        case email
        case displayName
        case signedInAt
        case signInMethod
        case isPro
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(Int64.self, forKey: .accountID)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        signedInAt = try container.decode(Date.self, forKey: .signedInAt)
        signInMethod = try container.decodeIfPresent(SignInMethod.self, forKey: .signInMethod) ?? .apple
        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
        isNewUser = false
    }
}
