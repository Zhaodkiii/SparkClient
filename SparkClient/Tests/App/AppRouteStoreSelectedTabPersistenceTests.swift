#if canImport(XCTest)
import XCTest

@testable import SparkClient

/// IOS26-TABBAR-000008：RootTabPreferenceStore 与 AppRouteStore 集成测试。
@MainActor
final class AppRouteStoreSelectedTabPersistenceTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppRouteStoreSelectedTabPersistenceTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        suiteName = nil
        super.tearDown()
    }

    private func makeStorage() -> UserDefaults {
        guard let storage = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        return storage
    }

    private func persistedRawValue(_ storage: UserDefaults) -> Int? {
        storage.object(forKey: RootTabPreferenceStore.storageKey) as? Int
    }

    // MARK: - 默认值与恢复

    func testDefaultTabIsChatWhenNoPersistedValue() {
        let store = AppRouteStore(storage: makeStorage())
        XCTAssertEqual(store.selectedTab, .chat)
    }

    func testRestorePersistedTabOnColdLaunch() {
        let storage = makeStorage()
        let first = AppRouteStore(storage: storage)
        first.selectedTab = .healthHome

        let second = AppRouteStore(storage: storage)
        XCTAssertEqual(second.selectedTab, .healthHome)
    }

    func testRestoreZeroRawValueHealthHome() {
        // rawValue = 0（healthHome）必须能和"未设置"区分开
        let storage = makeStorage()
        storage.set(AppRouteStore.RootTab.healthHome.rawValue, forKey: RootTabPreferenceStore.storageKey)

        let store = AppRouteStore(storage: storage)
        XCTAssertEqual(store.selectedTab, .healthHome)
    }

    func testInvalidRawValueFallsBackToChat() {
        let storage = makeStorage()
        storage.set(999, forKey: RootTabPreferenceStore.storageKey)

        let store = AppRouteStore(storage: storage)
        XCTAssertEqual(store.selectedTab, .chat)
    }

    func testNonIntegerPersistedValueFallsBackToChat() {
        let storage = makeStorage()
        storage.set("not-a-tab", forKey: RootTabPreferenceStore.storageKey)

        let store = AppRouteStore(storage: storage)
        XCTAssertEqual(store.selectedTab, .chat)
    }

    // MARK: - 切换持久化

    func testUserTabSwitchPersistsRawValue() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)

        store.selectedTab = .settings

        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.settings.rawValue)
        XCTAssertEqual(AppRouteStore(storage: storage).selectedTab, .settings)
    }

    func testSettingSameTabDoesNotRewriteStorage() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)
        store.selectedTab = .chat
        storage.removeObject(forKey: RootTabPreferenceStore.storageKey)

        store.selectedTab = .chat

        XCTAssertNil(persistedRawValue(storage))
    }

    // MARK: - 程序化路由

    func testRouteUpdatesPersistedTab() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)
        let threadID = UUID()

        store.route(to: .chatThread(threadID))

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.chat.rawValue)
    }

    func testRouteToDeepLinkOverridesPersistedTab() {
        // 深链/通知等显式路由优先于冷启动持久化 tab
        let storage = makeStorage()
        storage.set(AppRouteStore.RootTab.settings.rawValue, forKey: RootTabPreferenceStore.storageKey)
        let store = AppRouteStore(storage: storage)

        store.route(to: .taskDetail(memberID: 1, taskID: 2))

        XCTAssertEqual(store.selectedTab, .healthHome)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.healthHome.rawValue)
    }

    func testReplaceStackUpdatesPersistedTab() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)

        store.replaceStack([.fitness], for: .fitness)

        XCTAssertEqual(store.selectedTab, .fitness)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.fitness.rawValue)
    }

    // MARK: - resetRouteGraph

    func testResetRouteGraphClearsStacksButPreservesSelectedTab() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)
        store.selectedTab = .nutrition
        store.route(to: .nutrition)

        store.resetRouteGraph()

        XCTAssertEqual(store.selectedTab, .nutrition)
        XCTAssertTrue(store.routeStacks.isEmpty)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.nutrition.rawValue)
    }

    // MARK: - 不可见 tab 兜底

    func testInvisibleTabFallsBackToDefaultChat() {
        let storage = makeStorage()
        storage.set(AppRouteStore.RootTab.nutrition.rawValue, forKey: RootTabPreferenceStore.storageKey)
        let store = AppRouteStore(storage: storage)

        // dashboard 布局下 nutrition 不可见，.chat 可见 → 兜底 .chat
        store.ensureSelectedTabIsVisible(visibleTabs: [.healthHome, .chat, .settings])

        XCTAssertEqual(store.selectedTab, .chat)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.chat.rawValue)
    }

    func testFallbackTabIsPersistedForNextLaunch() {
        let storage = makeStorage()
        storage.set(AppRouteStore.RootTab.nutrition.rawValue, forKey: RootTabPreferenceStore.storageKey)
        let store = AppRouteStore(storage: storage)

        store.ensureSelectedTabIsVisible(visibleTabs: [.healthHome, .chat, .settings])

        XCTAssertEqual(AppRouteStore(storage: storage).selectedTab, .chat)
    }

    func testFallsBackToFirstVisibleTabWhenChatInvisible() {
        let storage = makeStorage()
        storage.set(AppRouteStore.RootTab.settings.rawValue, forKey: RootTabPreferenceStore.storageKey)
        let store = AppRouteStore(storage: storage)

        // 未来布局：.chat 也不可见 → 取第一个可见 tab
        store.ensureSelectedTabIsVisible(visibleTabs: [.healthHome, .fitness])

        XCTAssertEqual(store.selectedTab, .healthHome)
        XCTAssertEqual(persistedRawValue(storage), AppRouteStore.RootTab.healthHome.rawValue)
    }

    func testVisibleTabIsKeptWithoutPersistenceRewrite() {
        let storage = makeStorage()
        let store = AppRouteStore(storage: storage)
        store.selectedTab = .healthHome
        storage.removeObject(forKey: RootTabPreferenceStore.storageKey)

        store.ensureSelectedTabIsVisible(visibleTabs: [.healthHome, .chat, .settings])

        XCTAssertEqual(store.selectedTab, .healthHome)
        XCTAssertNil(persistedRawValue(storage))
    }
}
#endif
