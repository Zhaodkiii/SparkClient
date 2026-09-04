#if canImport(XCTest)
import XCTest

@testable import SparkClient

/// IOS26-TABBAR-000009：医院根 Tab 路由归属与持久化恢复测试。
@MainActor
final class AppRouteStoreHospitalTabTests: XCTestCase {
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppRouteStoreHospitalTabTests.\(UUID().uuidString)"
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

    // MARK: - 路由归属

    func testHospitalRoutesBelongToHospitalRootTab() {
        XCTAssertEqual(AppRoute.hospitalHome.rootTab, .hospital)
        XCTAssertEqual(AppRoute.hospitalAgentDirectory(departmentID: UUID()).rootTab, .hospital)
        XCTAssertEqual(AppRoute.hospitalAgentDirectory(departmentID: nil).rootTab, .hospital)
    }

    func testHospitalHomeIsRootDestinationAndDirectoryIsPushed() {
        XCTAssertTrue(AppRoute.hospitalHome.isRootDestination)
        XCTAssertFalse(AppRoute.hospitalAgentDirectory(departmentID: nil).isRootDestination)
    }

    // MARK: - raw value 与持久化

    func testHospitalRootTabUsesNewRawValue() {
        // 31.1：既有 RootTab raw value 不被重排；医院 Tab 使用独立 raw value 10。
        XCTAssertEqual(AppRouteStore.RootTab.hospital.rawValue, 10)
        XCTAssertEqual(AppRouteStore.RootTab.healthHome.rawValue, 0)
        XCTAssertEqual(AppRouteStore.RootTab.chat.rawValue, 3)
        XCTAssertEqual(AppRouteStore.RootTab.settings.rawValue, 4)
    }

    func testHospitalTabSelectionPersistsAcrossColdLaunch() {
        let storage = makeStorage()
        let first = AppRouteStore(storage: storage)
        first.selectedTab = .hospital

        let second = AppRouteStore(storage: storage)
        XCTAssertEqual(second.selectedTab, .hospital)
    }
}
#endif
