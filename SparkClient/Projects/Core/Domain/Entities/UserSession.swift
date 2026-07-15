import Foundation

nonisolated struct UserSession: Codable, Equatable, Sendable {
    nonisolated enum SignInMethod: String, Codable, Sendable {
        case device
        case apple
        case google
        case phone
        case email
    }

    let accountID: Int64
    let email: String
    let displayName: String
    let signedInAt: Date
    let signInMethod: SignInMethod
    let isPro: Bool
    let isNewUser: Bool
    /// 以服务端 `is_device_account` 为准；旧快照缺省为 false。
    let isDeviceAccount: Bool

    init(
        accountID: Int64,
        email: String,
        displayName: String,
        signedInAt: Date,
        signInMethod: SignInMethod = .apple,
        isPro: Bool = false,
        isNewUser: Bool = false,
        isDeviceAccount: Bool = false
    ) {
        self.accountID = accountID
        self.email = email
        self.displayName = displayName
        self.signedInAt = signedInAt
        self.signInMethod = signInMethod
        self.isPro = isPro
        self.isNewUser = isNewUser
        self.isDeviceAccount = isDeviceAccount
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
        isDeviceAccount = try container.decodeIfPresent(Bool.self, forKey: .key("isDeviceAccount")) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodableKey.self)
        try container.encode(accountID, forKey: .key("accountId"))
        try container.encode(email, forKey: .key("email"))
        try container.encode(displayName, forKey: .key("displayName"))
        try container.encode(signedInAt, forKey: .key("signedInAt"))
        try container.encode(signInMethod, forKey: .key("signInMethod"))
        try container.encode(isPro, forKey: .key("isPro"))
        try container.encode(isNewUser, forKey: .key("isNewUser"))
        try container.encode(isDeviceAccount, forKey: .key("isDeviceAccount"))
    }
}

nonisolated enum AccountResolution: String, Codable, Sendable {
    case deviceAccountCreated = "device_account_created"
    case deviceAccountLogin = "device_account_login"
    case deviceAccountRecreated = "device_account_recreated"
    case deviceAccountUpgraded = "device_account_upgraded"
    case formalAccountCreated = "formal_account_created"
    case formalAccountRecreated = "formal_account_recreated"
    case existingIdentityLogin = "existing_identity_login"
}
