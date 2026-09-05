#if canImport(XCTest)
import Foundation
import XCTest
@testable import SparkClient

/// 线上问诊用例测试（DOCTOR-WORKSPACE-000004 页面形态修订）。
final class ConsultationUseCaseTests: XCTestCase {
    func testSubmitConsultationSubmitsPayloadAndRemembersScope() async throws {
        let remote = StubHospitalCareRemoteAPI()
        let scopeStore = HospitalConversationScopeStore()
        let agentID = UUID()
        let threadID = UUID()
        let hospitalID = UUID()
        remote.submitConsultationResult = .success(
            HospitalCareTestFixtures.consultationDTO(threadID: threadID, agentID: agentID, memberID: 7, hospitalID: hospitalID)
        )
        let useCase = SubmitConsultationUseCase(remoteAPI: remote, scopeStore: scopeStore)
        let draftThreadID = UUID()

        let consultation = try await useCase.execute(
            accountID: 42,
            input: SubmitConsultationUseCase.Input(
                agentID: agentID,
                memberID: 7,
                hospitalID: hospitalID,
                chiefComplaint: "最近胸口闷",
                attachmentFileIDs: [11, 12],
                orderItems: ["复诊开药"],
                pastHistory: "高血压三年",
                familyHistory: "",
                allergyHistory: "青霉素过敏",
                threadID: draftThreadID
            )
        )

        XCTAssertEqual(consultation.threadId, threadID)
        XCTAssertEqual(remote.submitConsultationCallCount, 1)
        let payload = try XCTUnwrap(remote.lastConsultationPayload)
        XCTAssertEqual(payload.agentId, agentID)
        XCTAssertEqual(payload.memberId, 7)
        XCTAssertEqual(payload.chiefComplaint, "最近胸口闷")
        XCTAssertEqual(payload.attachments?.map(\.fileId), [11, 12])
        XCTAssertEqual(payload.orderItems, ["复诊开药"])
        XCTAssertEqual(payload.pastHistory, "高血压三年")
        XCTAssertNil(payload.familyHistory)
        XCTAssertEqual(payload.threadId, draftThreadID)

        // 提交成功后记录问诊会话 scope，供分类器识别为线上问诊。
        let scope = scopeStore.scope(for: threadID, accountID: 42)
        XCTAssertEqual(scope?.agentID, agentID)
        XCTAssertEqual(scope?.memberID, 7)
        XCTAssertEqual(scope?.hospitalID, hospitalID)
        XCTAssertEqual(scope?.consultationID, consultation.consultationId)
        XCTAssertEqual(scope?.consultNo, consultation.consultNo)
    }

    func testSubmitConsultationWithoutAttachmentsOmitsOptionalFields() async throws {
        let remote = StubHospitalCareRemoteAPI()
        let scopeStore = HospitalConversationScopeStore()
        remote.submitConsultationResult = .success(HospitalCareTestFixtures.consultationDTO())
        let useCase = SubmitConsultationUseCase(remoteAPI: remote, scopeStore: scopeStore)

        _ = try await useCase.execute(
            accountID: 42,
            input: SubmitConsultationUseCase.Input(
                agentID: UUID(),
                memberID: 7,
                hospitalID: UUID(),
                chiefComplaint: "咳嗽三天",
                attachmentFileIDs: [],
                orderItems: [],
                pastHistory: "",
                familyHistory: "",
                allergyHistory: "",
                threadID: UUID()
            )
        )

        let payload = try XCTUnwrap(remote.lastConsultationPayload)
        XCTAssertNil(payload.attachments)
        XCTAssertNil(payload.orderItems)
        XCTAssertNil(payload.pastHistory)
        XCTAssertNil(payload.allergyHistory)
    }

    func testSubmitConsultationFailureDoesNotRememberScope() async {
        let remote = StubHospitalCareRemoteAPI()
        let scopeStore = HospitalConversationScopeStore()
        remote.submitConsultationResult = .failure(StubHospitalCareRemoteAPI.StubError.network)
        let useCase = SubmitConsultationUseCase(remoteAPI: remote, scopeStore: scopeStore)
        let threadID = UUID()

        do {
            _ = try await useCase.execute(
                accountID: 42,
                input: SubmitConsultationUseCase.Input(
                    agentID: UUID(),
                    memberID: 7,
                    hospitalID: UUID(),
                    chiefComplaint: "头疼",
                    attachmentFileIDs: [],
                    orderItems: [],
                    pastHistory: "",
                    familyHistory: "",
                    allergyHistory: "",
                    threadID: threadID
                )
            )
            XCTFail("期望提交失败抛错")
        } catch {
            XCTAssertNil(scopeStore.scope(for: threadID, accountID: 42))
        }
    }

    func testLoadConsultationsReturnsRemoteItems() async throws {
        let remote = StubHospitalCareRemoteAPI()
        remote.consultationsResult = .success([
            HospitalCareTestFixtures.consultationDTO(consultNo: "C202609050001"),
            HospitalCareTestFixtures.consultationDTO(consultNo: "C202609050002"),
        ])
        let useCase = LoadConsultationsUseCase(remoteAPI: remote)

        let items = try await useCase.execute(memberID: 7)

        XCTAssertEqual(items.map(\.consultNo), ["C202609050001", "C202609050002"])
    }

    func testLandingFocusKeepsRecentAfterSubmit() {
        let ended = HospitalCareTestFixtures.consultationDTO(serviceStatus: "ended")
        XCTAssertEqual(
            ConsultLandingFocus.resolve(requested: .recent, consultations: [ended]),
            .recent
        )
    }

    func testLandingFocusSwitchesToRecentWhenInProgressExists() {
        let pending = HospitalCareTestFixtures.consultationDTO(serviceStatus: "pending_doctor")
        let inProgress = HospitalCareTestFixtures.consultationDTO(serviceStatus: "doctor_joined")
        XCTAssertTrue(ConsultationStatusText.isInProgress("pending_doctor"))
        XCTAssertTrue(ConsultationStatusText.isInProgress("doctor_joined"))
        XCTAssertEqual(
            ConsultLandingFocus.resolve(requested: .departments, consultations: [pending]),
            .recent
        )
        XCTAssertEqual(
            ConsultLandingFocus.resolve(requested: .departments, consultations: [inProgress]),
            .recent
        )
    }

    func testLandingFocusStaysDepartmentsWhenNoInProgress() {
        let ended = HospitalCareTestFixtures.consultationDTO(serviceStatus: "ended")
        XCTAssertFalse(ConsultationStatusText.isInProgress("ended"))
        XCTAssertEqual(
            ConsultLandingFocus.resolve(requested: .departments, consultations: [ended]),
            .departments
        )
        XCTAssertEqual(
            ConsultLandingFocus.resolve(requested: .departments, consultations: []),
            .departments
        )
    }
}
#endif
