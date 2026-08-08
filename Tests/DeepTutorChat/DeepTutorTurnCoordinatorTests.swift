import XCTest
@testable import SparkClient

final class DeepTutorTurnCoordinatorTests: XCTestCase {
    func testCapabilityStagePipelineIsNonEmpty() {
        for capability in DeepTutorCapability.allCases {
            XCTAssertFalse(capability.stagePipeline.isEmpty, capability.rawValue)
            XCTAssertEqual(capability.initialStage, capability.stagePipeline.first)
        }
    }

    func testSnapshotTurnEnvelopeRoundTrip() {
        let turnID = UUID()
        let snapshot = DeepTutorRequestSnapshot(capability: .chat)
            .appendingTurnEnvelope(
                turnID: turnID,
                resumeMode: .liveSend,
                capabilityStage: .exploring,
                modelResolutionMode: .liveSend
            )
        XCTAssertEqual(snapshot.turnID, turnID)
        XCTAssertEqual(snapshot.resumeMode, DeepTutorTurnResumeMode.liveSend.rawValue)
        XCTAssertEqual(snapshot.capabilityStage, DeepTutorCapabilityStage.exploring.rawValue)
        XCTAssertEqual(snapshot.modelResolutionMode, "live_send")
    }

    func testTurnResumeModeCodable() throws {
        let modes: [DeepTutorTurnResumeMode] = [
            .liveSend,
            .replaySnapshot,
            .askUserResume,
            .memberSelectionResume,
        ]
        for mode in modes {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DeepTutorTurnResumeMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
