import Foundation

nonisolated struct UserSession: Codable, Equatable, Sendable {
    nonisolated enum SignInMethod: String, Codable, Sendable {
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


    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodableKey.self)
        accountID = try container.decode(Int64.self, forKey: .key("accountId"))
        email = try container.decode(String.self, forKey: .key("email"))
        displayName = try container.decode(String.self, forKey: .key("displayName"))
        signedInAt = try container.decode(Date.self, forKey: .key("signedInAt"))
        signInMethod = try container.decodeIfPresent(SignInMethod.self, forKey: .key("signInMethod")) ?? .apple
        isPro = try container.decodeIfPresent(Bool.self, forKey: .key("isPro")) ?? false
        isNewUser = false
    }
}
