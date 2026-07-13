#if canImport(XCTest)
import XCTest

final class NotificationEnvelopeTests: XCTestCase {
    func testDecodesKnownActionAndNumericParameters() {
        let envelope = NotificationEnvelopeDecoder.decode(userInfo: [
            "schema_version": 1,
            "notification_id": "notification-1",
            "business_scene": "medical.resource.updated",
            "business_type": "medical.resource",
            "occurred_at": "2026-07-13T10:20:30+08:00",
            "action": [
                "type": "open_medical_resource",
                "params": ["member_id": 12, "resource_type": "medication_plan", "resource_id": 98]
            ]
        ])

        XCTAssertEqual(envelope?.businessScene, "medical.resource.updated")
        XCTAssertEqual(
            envelope.map { NotificationActionRouter().destination(for: $0) },
            .medicalResource(memberID: "12", resourceType: "medication_plan", resourceID: "98")
        )
    }

    func testUnknownSceneDoesNotPreventKnownAction() {
        let envelope = decode(scene: "future.domain.new_event", actionType: "open_app_update")
        XCTAssertEqual(envelope.map { NotificationActionRouter().destination(for: $0) }, .appUpdate)
    }

    func testUnknownActionFallsBackToNotificationCenter() {
        let envelope = decode(scene: "system.announcement.published", actionType: "execute_arbitrary_url")
        XCTAssertEqual(envelope?.action, .unknown(type: "execute_arbitrary_url"))
        XCTAssertEqual(envelope.map { NotificationActionRouter().destination(for: $0) }, .notificationCenter)
    }

    func testFutureSchemaDoesNotExecuteKnownAction() {
        var payload = basePayload(scene: "system.app_version.update_available", actionType: "open_app_update")
        payload["schema_version"] = 99
        let envelope = NotificationEnvelopeDecoder.decode(userInfo: payload)!
        XCTAssertFalse(envelope.canExecuteAction)
        XCTAssertEqual(NotificationActionRouter().destination(for: envelope), .notificationCenter)
    }

    func testMissingRequiredActionParameterBecomesUnknown() {
        var payload = basePayload(scene: "task.reminder.due", actionType: "open_task")
        payload["action"] = ["type": "open_task", "params": [:]]
        let envelope = NotificationEnvelopeDecoder.decode(userInfo: payload)!
        XCTAssertEqual(envelope.action, .unknown(type: "open_task"))
    }

    func testNestedEnvelopeIsSupported() {
        let envelope = NotificationEnvelopeDecoder.decode(userInfo: [
            "aps": ["alert": "test"],
            "envelope": basePayload(scene: "system.announcement.published", actionType: "open_notification_center")
        ])
        XCTAssertEqual(envelope?.notificationID, "notification-1")
    }

    private func decode(scene: String, actionType: String) -> NotificationEnvelope? {
        NotificationEnvelopeDecoder.decode(userInfo: basePayload(scene: scene, actionType: actionType))
    }

    private func basePayload(scene: String, actionType: String) -> [AnyHashable: Any] {
        [
            "schema_version": 1,
            "notification_id": "notification-1",
            "business_scene": scene,
            "business_type": "system.announcement",
            "action": ["type": actionType, "params": [:]]
        ]
    }
}
#endif
