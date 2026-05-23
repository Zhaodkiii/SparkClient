#if canImport(XCTest)
import XCTest

@MainActor
final class AddFamilyMemberViewModelTests: XCTestCase {
    func testDefaultModeIsCreate() {
        let viewModel = AddFamilyMemberViewModel(mode: .create, shareUseCase: nil)
        if case .create = viewModel.mode {
            XCTAssertTrue(viewModel.canShowScanner == false)
        } else {
            XCTFail("expected create mode")
        }
    }

    func testCancelBindModeResetsToCreate() {
        let viewModel = AddFamilyMemberViewModel(mode: .create, shareUseCase: nil)
        viewModel.mode = .bind(ticket: "spark_member_share.test", resolved: Self.sampleResolve(alreadyBound: false))
        viewModel.relationshipCode = "son"
        viewModel.cancelBindMode()
        if case .create = viewModel.mode {
            XCTAssertEqual(viewModel.relationshipCode, MemberRelationshipCatalog.defaultCode)
        } else {
            XCTFail("expected create mode after cancel")
        }
    }

    func testCanShowScannerOnlyInCreateMode() {
        let engine = SparkNetworkEngine()
        let config = SparkBackendConfiguration(engine: engine, logger: ConsoleLogger())
        let viewModel = AddFamilyMemberViewModel(
            mode: .create,
            shareUseCase: ShareMemberUseCase(memberAPI: SparkMedicalMemberAPI(configuration: config))
        )
        XCTAssertTrue(viewModel.canShowScanner)
        viewModel.mode = .bind(ticket: "t", resolved: Self.sampleResolve(alreadyBound: false))
        XCTAssertFalse(viewModel.canShowScanner)
    }

    private static func sampleResolve(alreadyBound: Bool) -> SparkMedicalMemberAPI.ShareResolveResponse {
        SparkMedicalMemberAPI.ShareResolveResponse(
            member: .init(id: 9, name: "张三", gender: "male", birthDate: nil, avatarUrl: ""),
            inviter: .init(userId: 1, displayName: "邀请人", relationship: "father"),
            defaultRole: "viewer",
            alreadyBound: alreadyBound,
            existingBindingId: alreadyBound ? 1 : nil,
            sharedUserCount: 1
        )
    }
}
#endif
