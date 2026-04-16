import Foundation
import Combine

struct CardActionSnapshot: Codable, Equatable, Sendable {
    let savedKnowledgeCardIDs: [UUID]
    let savedMessageIDs: [UUID]
    let ignoredTaskCardIDs: [Int]
    let createdTaskCardIDs: [Int]

    static let empty = CardActionSnapshot(
        savedKnowledgeCardIDs: [],
        savedMessageIDs: [],
        ignoredTaskCardIDs: [],
        createdTaskCardIDs: []
    )
}

/// Chat 页面统一 UI 状态中心：
/// - 所有消息级状态（翻译、保存、任务卡 loading 等）集中存放；
/// - 避免 View 层散落大量 `@State`，减少状态同步错误。
@MainActor
final class ChatMessageUIStateStore: ObservableObject {
    @Published private(set) var deletedMessageIDs: Set<UUID> = []
    @Published private(set) var translatedTexts: [UUID: String] = [:]
    @Published private(set) var isTranslatingMessageIDs: Set<UUID> = []
    @Published private(set) var mathModeMessageIDs: Set<UUID> = []
    @Published private(set) var generatedKnowledgeCards: [UUID: [ChatKnowledgeCard]] = [:]
    @Published private(set) var savingKnowledgeCardIDs: Set<UUID> = []
    @Published private(set) var savedKnowledgeCardIDs: Set<UUID> = []
    @Published private(set) var isSavingMessageIDs: Set<UUID> = []
    @Published private(set) var savedMessageIDs: Set<UUID> = []
    @Published private(set) var taskCardLoadingIDs: Set<Int> = []
    @Published private(set) var ignoredTaskCardIDs: Set<Int> = []
    @Published private(set) var createdTaskCardIDs: Set<Int> = []
    @Published private(set) var savingMedicalCardIDs: Set<UUID> = []

    func isDeleted(_ id: UUID) -> Bool { deletedMessageIDs.contains(id) }
    func markDeleted(_ id: UUID) { deletedMessageIDs.insert(id) }

    func translatedText(for id: UUID) -> String? { translatedTexts[id] }
    func setTranslatedText(_ value: String?, for id: UUID) { translatedTexts[id] = value }

    func isTranslating(_ id: UUID) -> Bool { isTranslatingMessageIDs.contains(id) }
    func setTranslating(_ value: Bool, for id: UUID) {
        if value {
            isTranslatingMessageIDs.insert(id)
        } else {
            isTranslatingMessageIDs.remove(id)
        }
    }

    func isMathMode(_ id: UUID) -> Bool { mathModeMessageIDs.contains(id) }
    func setMathMode(_ value: Bool, for id: UUID) {
        if value {
            mathModeMessageIDs.insert(id)
        } else {
            mathModeMessageIDs.remove(id)
        }
    }

    func knowledgeCards(for id: UUID) -> [ChatKnowledgeCard] { generatedKnowledgeCards[id] ?? [] }
    func setKnowledgeCards(_ cards: [ChatKnowledgeCard], for id: UUID) {
        generatedKnowledgeCards[id] = cards
    }

    func isKnowledgeCardSaving(_ id: UUID) -> Bool { savingKnowledgeCardIDs.contains(id) }
    func setKnowledgeCardSaving(_ value: Bool, for id: UUID) {
        if value {
            savingKnowledgeCardIDs.insert(id)
        } else {
            savingKnowledgeCardIDs.remove(id)
        }
    }

    func isKnowledgeCardSaved(_ id: UUID) -> Bool { savedKnowledgeCardIDs.contains(id) }
    func setKnowledgeCardSaved(_ value: Bool, for id: UUID) {
        if value {
            savedKnowledgeCardIDs.insert(id)
        } else {
            savedKnowledgeCardIDs.remove(id)
        }
    }

    func isMessageSaving(_ id: UUID) -> Bool { isSavingMessageIDs.contains(id) }
    func setMessageSaving(_ value: Bool, for id: UUID) {
        if value {
            isSavingMessageIDs.insert(id)
        } else {
            isSavingMessageIDs.remove(id)
        }
    }

    func isMessageSaved(_ id: UUID) -> Bool { savedMessageIDs.contains(id) }
    func setMessageSaved(_ value: Bool, for id: UUID) {
        if value {
            savedMessageIDs.insert(id)
        } else {
            savedMessageIDs.remove(id)
        }
    }

    func isTaskCardLoading(_ id: Int) -> Bool { taskCardLoadingIDs.contains(id) }
    func setTaskCardLoading(_ value: Bool, for id: Int) {
        if value {
            taskCardLoadingIDs.insert(id)
        } else {
            taskCardLoadingIDs.remove(id)
        }
    }

    func isTaskCardIgnored(_ id: Int) -> Bool { ignoredTaskCardIDs.contains(id) }
    func ignoreTaskCard(_ id: Int) { ignoredTaskCardIDs.insert(id) }

    func isTaskCardCreated(_ id: Int) -> Bool { createdTaskCardIDs.contains(id) }
    func markTaskCardCreated(_ id: Int) { createdTaskCardIDs.insert(id) }

    func isMedicalCardSaving(_ id: UUID) -> Bool { savingMedicalCardIDs.contains(id) }
    func setMedicalCardSaving(_ value: Bool, for id: UUID) {
        if value {
            savingMedicalCardIDs.insert(id)
        } else {
            savingMedicalCardIDs.remove(id)
        }
    }

    func makeCardActionSnapshot() -> CardActionSnapshot {
        CardActionSnapshot(
            savedKnowledgeCardIDs: Array(savedKnowledgeCardIDs),
            savedMessageIDs: Array(savedMessageIDs),
            ignoredTaskCardIDs: Array(ignoredTaskCardIDs),
            createdTaskCardIDs: Array(createdTaskCardIDs)
        )
    }

    func applyCardActionSnapshot(_ snapshot: CardActionSnapshot, forceReload: Bool) {
        if forceReload {
            savedKnowledgeCardIDs = []
            savedMessageIDs = []
            ignoredTaskCardIDs = []
            createdTaskCardIDs = []
        }
        guard forceReload ||
                (savedKnowledgeCardIDs.isEmpty &&
                 savedMessageIDs.isEmpty &&
                 ignoredTaskCardIDs.isEmpty &&
                 createdTaskCardIDs.isEmpty) else {
            return
        }
        savedKnowledgeCardIDs = Set(snapshot.savedKnowledgeCardIDs)
        savedMessageIDs = Set(snapshot.savedMessageIDs)
        ignoredTaskCardIDs = Set(snapshot.ignoredTaskCardIDs)
        createdTaskCardIDs = Set(snapshot.createdTaskCardIDs)
    }
}
