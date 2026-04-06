import Foundation

final class SessionBackedUserProfileRepository: UserProfileRepository {
    private let snapshotStore: SessionSnapshotStore

    init(snapshotStore: SessionSnapshotStore = SessionSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    func upsertProfile(
        email: String,
        displayName: String,
        signedInAt: Date
    ) async throws -> UserProfile {
        if let existing = await snapshotStore.load() {
            return UserProfile(
                id: existing.profileID,
                email: email,
                displayName: displayName,
                createdAt: existing.signedInAt,
                lastSignedInAt: signedInAt
            )
        }

        let profileID = UUID()
        return UserProfile(
            id: profileID,
            email: email,
            displayName: displayName,
            createdAt: signedInAt,
            lastSignedInAt: signedInAt
        )
    }

    func fetchProfile(id: UUID) async throws -> UserProfile? {
        guard let session = await snapshotStore.load(), session.profileID == id else { return nil }
        return UserProfile(
            id: session.profileID,
            email: session.email,
            displayName: session.displayName,
            createdAt: session.signedInAt,
            lastSignedInAt: session.signedInAt
        )
    }

    func fetchLastActiveProfile() async throws -> UserProfile? {
        guard let session = await snapshotStore.load() else { return nil }
        return UserProfile(
            id: session.profileID,
            email: session.email,
            displayName: session.displayName,
            createdAt: session.signedInAt,
            lastSignedInAt: session.signedInAt
        )
    }
}
