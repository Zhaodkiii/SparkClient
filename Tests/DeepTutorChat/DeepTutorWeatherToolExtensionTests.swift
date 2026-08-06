import XCTest
@testable import SparkClient

final class DeepTutorWeatherToolExtensionTests: XCTestCase {
    func testBeijingWeatherIntentMountsWeatherTools() {
        let intents = DeepTutorToolIntentClassifier.classify(
            userInput: "北京今天的天气怎么样？",
            capability: .chat
        )
        XCTAssertTrue(intents.contains(where: { $0.domain == .weatherLocation }))

        let policy = DeepTutorToolPolicyResolver.resolve(
            makeContext(userInput: "北京今天的天气怎么样？")
        )
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.queryLocation.rawValue))
    }

    func testAppleWeatherReferenceStillMountsWeatherTools() {
        let intents = DeepTutorToolIntentClassifier.classify(
            userInput: "Apple 天气显示今天下雨，你帮我查一下上海天气。",
            capability: .chat
        )
        XCTAssertTrue(intents.contains(where: { $0.domain == .weatherLocation }))

        let policy = DeepTutorToolPolicyResolver.resolve(
            makeContext(userInput: "Apple 天气显示今天下雨，你帮我查一下上海天气。")
        )
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
    }

    func testWeatherKitProductQuestionDoesNotMountWeatherTools() {
        let intents = DeepTutorToolIntentClassifier.classify(
            userInput: "Apple WeatherKit 是什么？",
            capability: .chat
        )
        XCTAssertFalse(intents.contains(where: { $0.domain == .weatherLocation }))

        let policy = DeepTutorToolPolicyResolver.resolve(
            makeContext(userInput: "Apple WeatherKit 是什么？")
        )
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
    }

    func testUnclearCityWithoutLocationPermissionPromptsAskUser() {
        let policy = DeepTutorToolPolicyResolver.resolve(
            makeContext(userInput: "今天的天气怎么样？")
        )
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.askUserQuestion.rawValue))
        XCTAssertTrue(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
    }

    func testAskUserResumeRestoresWeatherTools() {
        let prior = DeepTutorPerTurnToolSnapshot(
            capability: .chat,
            requestedCanonicalTools: [],
            resolvedCanonicalTools: [],
            resolvedSparkToolNames: [
                SparkToolName.askUserQuestion.rawValue,
                SparkToolName.queryWeather.rawValue,
                SparkToolName.queryLocation.rawValue,
            ],
            autoMountedCanonicalTools: [],
            suppressedCanonicalTools: [],
            aliasFailures: [],
            intentHints: ["weather_location"],
            structuredIntents: [
                DeepTutorStructuredToolIntent(
                    domain: .weatherLocation,
                    subdomain: nil,
                    timeRange: .today,
                    dateAnchor: nil,
                    memberRequirement: false,
                    confidence: .high
                )
            ],
            policyReason: "weather_city_prompt",
            mountFlags: [:],
            modelSupportsNativeTools: true,
            toolPhase: "weather_city_prompt",
            domainExtensionSources: ["weather_location"]
        )

        var context = makeContext(userInput: "今天的天气怎么样？")
        let resumed = DeepTutorToolPolicyResolver.resolveForAskUserResume(
            context: context,
            originalUserPrompt: "今天的天气怎么样？",
            answerSummary: "上海",
            priorSnapshot: prior
        )

        XCTAssertFalse(resumed.allowedToolNames.contains(SparkToolName.askUserQuestion.rawValue))
        XCTAssertTrue(resumed.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
        XCTAssertTrue(resumed.allowedToolNames.contains(SparkToolName.queryLocation.rawValue))
    }

    func testWeatherDisabledDoesNotMountWeatherTools() {
        let policy = DeepTutorToolPolicyResolver.resolve(
            makeContext(userInput: "北京今天的天气怎么样？", weatherToolEnabled: false)
        )
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.queryWeather.rawValue))
        XCTAssertFalse(policy.allowedToolNames.contains(SparkToolName.queryLocation.rawValue))
    }

    private func makeContext(userInput: String, weatherToolEnabled: Bool = true) -> DeepTutorToolMountContext {
        var context = DeepTutorToolMountContext.default(
            capability: .chat,
            userInput: userInput,
            conversationID: UUID(),
            conversationTitle: "Test"
        )
        context.hasLocationPermission = false
        context.weatherToolEnabled = weatherToolEnabled
        return context
    }
}
