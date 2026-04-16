import Foundation

final class SessionBackedUserProfileRepository: UserProfileRepository {
    private let snapshotStore: SessionSnapshotStore

    init(snapshotStore: SessionSnapshotStore = SessionSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    func upsertProfile(
        accountID: Int64,
        email: String,
        displayName: String,
        signedInAt: Date,
        signInMethod: UserSession.SignInMethod
    ) async throws -> UserProfile {
        let normalizedEmail = normalizeAccountIdentifier(email, signInMethod: signInMethod)

        if let existing = await snapshotStore.load(), existing.accountID == accountID {
            return UserProfile(
                id: existing.accountID,
                email: normalizedEmail,
                displayName: displayName,
                createdAt: existing.signedInAt,
                lastSignedInAt: signedInAt
            )
        }

        return UserProfile(
            id: accountID,
            email: normalizedEmail,
            displayName: displayName,
            createdAt: signedInAt,
            lastSignedInAt: signedInAt
        )
    }

    func fetchProfile(id: Int64) async throws -> UserProfile? {
        guard let session = await snapshotStore.load(), session.accountID == id else { return nil }
        return UserProfile(
            id: session.accountID,
            email: session.email,
            displayName: session.displayName,
            createdAt: session.signedInAt,
            lastSignedInAt: session.signedInAt
        )
    }

    func fetchLastActiveProfile() async throws -> UserProfile? {
        guard let session = await snapshotStore.load() else { return nil }
        return UserProfile(
            id: session.accountID,
            email: session.email,
            displayName: session.displayName,
            createdAt: session.signedInAt,
            lastSignedInAt: session.signedInAt
        )
    }

    private func normalizeAccountIdentifier(
        _ rawValue: String,
        signInMethod: UserSession.SignInMethod
    ) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch signInMethod {
        case .apple:
            return trimmed.lowercased()
        case .phone:
            return trimmed.replacingOccurrences(of: " ", with: "")
        }
    }
}
