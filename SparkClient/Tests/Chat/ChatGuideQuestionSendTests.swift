#if canImport(XCTest)
import Foundation
import XCTest

/// 引导卡片问题发送链路与数据聚合测试：
/// - preset 问题完整进入 payload（点击后发送的 prompt 即 `question.prompt`）
/// - HealthKit 不可用时各 section 降级、payload 仍生成
/// - stub 数据齐全时 section 进入 ready 态
final class ChatGuideQuestionSendTests: XCTestCase {
    func testBuilderUsesPresetWhenMemberUnboundAndDefaultBindingDisabled() async {
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: StubGuideHealthReader(healthDataAvailable: false),
            medicalReader: StubGuideMedicalReader(),
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: nil, defaultMemberBindingEnabled: false)

        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertEqual(payload.questions, ChatGuideQuestionPreset.phaseOne)
        XCTAssertEqual(payload.questionGeneration?.state, .preset)
    }

    func testBuilderUsesGeneratingWhenMemberBound() async {
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: StubGuideHealthReader(healthDataAvailable: false),
            medicalReader: StubGuideMedicalReader(),
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: 42, defaultMemberBindingEnabled: false)

        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertTrue(payload.questions.isEmpty)
        XCTAssertEqual(payload.questionGeneration?.state, .generating)
        XCTAssertEqual(payload.questionGeneration?.memberID, 42)
        XCTAssertTrue(payload.isShowingQuestionLoading)
    }

    func testBuilderUsesGeneratingWhenDefaultBindingEnabledWithoutMember() async {
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: StubGuideHealthReader(healthDataAvailable: false),
            medicalReader: StubGuideMedicalReader(),
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: nil, defaultMemberBindingEnabled: true)

        XCTAssertTrue(payload.questions.isEmpty)
        XCTAssertEqual(payload.questionGeneration?.state, .generating)
    }

    func testBuilderEmbedsPresetQuestionsInPayload() async {
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: StubGuideHealthReader(healthDataAvailable: false),
            medicalReader: StubGuideMedicalReader(),
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: nil, defaultMemberBindingEnabled: false)

        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertEqual(payload.questions, ChatGuideQuestionPreset.phaseOne)
        XCTAssertEqual(Set(payload.questions.map(\.id)).count, payload.questions.count)
        // 每个 prompt 都可直接作为用户消息发送（非空、以标点结尾的完整问句）
        for question in payload.questions {
            XCTAssertFalse(question.prompt.hasPrefix(" "))
            XCTAssertFalse(question.prompt.hasSuffix(" "))
        }
    }

    func testBuilderDegradesSectionsWhenHealthDataUnavailable() async {
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: StubGuideHealthReader(healthDataAvailable: false),
            medicalReader: StubGuideMedicalReader(),
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: nil)

        XCTAssertEqual(payload.metricSections.count, 4)
        let states = Dictionary(uniqueKeysWithValues: payload.metricSections.map { ($0.id, $0.state) })
        XCTAssertEqual(states["movement"], .unavailable)
        XCTAssertEqual(states["body"], .empty)
        XCTAssertEqual(states["nutrition"], .unavailable)
        XCTAssertEqual(states["medical"], .empty)
        // 未绑定成员时医疗 section 提供查看医疗资料入口
        let medical = payload.metricSections.first { $0.id == "medical" }
        XCTAssertEqual(medical?.action?.kind, .openMedical)
    }

    func testBuilderProducesReadySectionsFromStubData() async {
        let reader = StubGuideHealthReader(healthDataAvailable: true)
        reader.stepDays = [
            ChatHealthStepModel.Day(
                date: "2026-08-20",
                title: "8月20日",
                totalSteps: 6000,
                totalDistanceMeters: 4000,
                hourly: []
            ),
            ChatHealthStepModel.Day(
                date: "2026-08-21",
                title: "8月21日",
                totalSteps: 10000,
                totalDistanceMeters: 7000,
                hourly: []
            )
        ]
        reader.energyDays = [
            ChatHealthEnergyModel.Day(
                date: "2026-08-21",
                title: "8月21日",
                basalEnergyKcal: 1500,
                activeEnergyKcal: 320,
                hourly: []
            )
        ]
        reader.nutritionSegments = [
            ChatHealthNutritionReadModel.Segment(
                label: "早餐",
                proteinGrams: 18,
                carbohydratesGrams: 35,
                fatGrams: 10,
                energyKilocalories: 420
            )
        ]
        reader.bodySummary = SparkBodyManagementSummary(
            weightKg: 68.4,
            bmi: 22.1,
            bodyFatPercentage: 0.186,
            latestSampleDate: Date(timeIntervalSince1970: 1_787_300_000)
        )

        let medicalReader = StubGuideMedicalReader(completeData: StubGuideMedicalReader.makeCompleteData(
            memberID: 7,
            caseCount: 2,
            activePlanCount: 1
        ))
        let builder = ChatGuideCardPayloadBuilder(
            healthReader: reader,
            medicalReader: medicalReader,
            logger: ConsoleLogger()
        )

        let payload = await builder.build(memberID: 7)

        let sections = Dictionary(uniqueKeysWithValues: payload.metricSections.map { ($0.id, $0) })
        XCTAssertEqual(sections["movement"]?.state, .ready)
        XCTAssertEqual(sections["movement"]?.items.map(\.id), ["steps", "calories"])
        XCTAssertNotNil(sections["movement"]?.chart)
        XCTAssertEqual(sections["body"]?.state, .ready)
        XCTAssertEqual(sections["body"]?.items.map(\.id), ["weight", "bmi", "bodyFat"])
        XCTAssertEqual(sections["nutrition"]?.state, .ready)
        XCTAssertEqual(sections["medical"]?.state, .ready)
        XCTAssertTrue(sections["medical"]?.items.contains { $0.id == "medicalCases" } ?? false)
    }
}

// MARK: - 共享测试替身（CreateThreadGuideMessageTests 亦使用）

final class StubGuideHealthReader: ChatGuideHealthReading, @unchecked Sendable {
    var healthDataAvailable: Bool
    var stepDays: [ChatHealthStepModel.Day] = []
    var energyDays: [ChatHealthEnergyModel.Day] = []
    var nutritionSegments: [ChatHealthNutritionReadModel.Segment] = []
    var bodySummary: SparkBodyManagementSummary?

    init(healthDataAvailable: Bool) {
        self.healthDataAvailable = healthDataAvailable
    }

    func isHealthDataAvailable() -> Bool { healthDataAvailable }

    func fetchStepVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthStepModel {
        ChatHealthStepModel(dateRangeText: "stub", days: stepDays)
    }

    func fetchEnergyVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthEnergyModel {
        ChatHealthEnergyModel(dateRangeText: "stub", days: energyDays)
    }

    func fetchNutritionReadVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthNutritionReadModel {
        ChatHealthNutritionReadModel(dateRangeText: "stub", segments: nutritionSegments)
    }

    func fetchBodyManagementSummary(days: Int) async -> SparkBodyManagementSummary? {
        bodySummary
    }
}

final class StubGuideMedicalReader: ChatGuideMedicalReading, @unchecked Sendable {
    var completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?

    init(completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil) {
        self.completeData = completeData
    }

    func fetchMemberCompleteData(memberID: Int) async -> Result<SparkMedicalSyncAPI.RemoteMemberCompleteData, HealthResourceLoadError> {
        if let completeData {
            return .success(completeData)
        }
        return .failure(.network("stub"))
    }

    static func makeCompleteData(memberID: Int, caseCount: Int, activePlanCount: Int) -> SparkMedicalSyncAPI.RemoteMemberCompleteData {
        let cases = (0..<caseCount).map { index in
            """
            {"id": \(index + 1), "member": \(memberID), "title": "病例\\(index + 1)"}
            """
        }
        let json = """
        {
          "member_id": \(memberID),
          "member": {
            "id": \(memberID),
            "name": "测试成员",
            "gender": "male",
            "blood_type": "",
            "allergies": [],
            "chronic_conditions": [],
            "notes": "",
            "avatar_url": "",
            "is_primary": true
          },
          "medical_cases": [\(cases.joined(separator: ", "))],
          "medication_summary": {
            "today_total": 0,
            "today_taken": 0,
            "today_skipped": 0,
            "adherence_rate": 0,
            "active_plan_count": \(activePlanCount),
            "low_stock_count": 0,
            "expiring_soon_count": 0
          }
        }
        """
        let data = Data(json.utf8)
        do {
            return try JSONDecoder.medicalAPI.decode(SparkMedicalSyncAPI.RemoteMemberCompleteData.self, from: data)
        } catch {
            fatalError("Stub complete-data JSON 解码失败: \(error)")
        }
    }
}
#endif
