import CoreData
import Foundation

final class CoreDataUserProfileRepository: UserProfileRepository {
    private let coreDataStack: CoreDataStack
    private let logger: Logger

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
        self.logger = logger
    }

    func upsertProfile(
        email: String,
        displayName: String,
        isDemo: Bool,
        signedInAt: Date
    ) async throws -> UserProfile {
        try await coreDataStack.performBackgroundTask { context in
            let request = UserProfileEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "email == %@", email)

            let entity = try context.fetch(request).first ?? UserProfileEntity(context: context)
            if entity.objectID.isTemporaryID {
                entity.id = UUID()
                entity.createdAt = signedInAt
            }
            entity.email = email
            entity.displayName = displayName
            entity.isDemo = isDemo
            entity.lastSignedInAt = signedInAt

            guard let profile = entity.toDomain() else {
                throw NSError(domain: "SparkClient.Profile", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法生成用户档案"])
            }
            return profile
        }
    }

    func fetchProfile(id: UUID) async throws -> UserProfile? {
        try await coreDataStack.performBackgroundTask { context in
            let request = UserProfileEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try context.fetch(request).first?.toDomain()
        }
    }

    func fetchLastActiveProfile() async throws -> UserProfile? {
        try await coreDataStack.performBackgroundTask { context in
            let request = UserProfileEntity.fetchRequest()
            request.fetchLimit = 1
            request.sortDescriptors = [NSSortDescriptor(key: "lastSignedInAt", ascending: false)]
            return try context.fetch(request).first?.toDomain()
        }
    }
}

private extension UserProfileEntity {
    func toDomain() -> UserProfile? {
        guard
            let id,
            let email,
            let displayName,
            let createdAt,
            let lastSignedInAt
        else {
            return nil
        }

        return UserProfile(
            id: id,
            email: email,
            displayName: displayName,
            isDemo: isDemo,
            createdAt: createdAt,
            lastSignedInAt: lastSignedInAt
        )
    }
}
