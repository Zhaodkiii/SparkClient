#if canImport(XCTest)
import XCTest

final class ChatCapabilityStrategyTests: XCTestCase {
    func testStandardChatStrategyUsesComposerFlagsDirectly() {
        let flags = ChatComposerRuntimeFlags(
            useTools: true,
            useKnowledgeBag: false,
            useWebSearch: true,
            reasoningEnabled: true,
            reasoningEffortTier: 2
        )
        let inference = ChatOrchestratorInferenceOptions.from(composerFlags: flags)
        let history = [makeUserMessage(text: "hello")]
        let modelAllowed: Set<String> = ["search_knowledge_bag", "fetch_step_details"]

        let output = StandardChatCapabilityStrategy().plan(
            ChatCapabilityStrategyInput(
                inference: inference,
                modelAllowedToolNames: modelAllowed,
                history: history,
                threadID: history[0].threadID,
                userQuestionForAI: "hello",
                hasHealthResourceContext: false
            )
        )

        XCTAssertEqual(output.inference.useTools, true)
        XCTAssertEqual(output.inference.useKnowledgeBag, false)
        XCTAssertEqual(output.inference.useWebSearch, true)
        XCTAssertEqual(output.inference.reasoningEnabled, true)
        XCTAssertEqual(output.inference.reasoningEffortTier, 2)
        XCTAssertEqual(output.inference.allowedToolNames, modelAllowed)
        XCTAssertEqual(output.aiHistory.count, 1)
        XCTAssertEqual(output.aiHistory[0].blocks.first?.text, "hello")
    }

    func testSmallTaskStrategyForcesToolsBasedOnTaskToolList() {
        let task = SmallTask.createLocalTask(
            id: 1,
            name: "Test Task",
            brief: "brief",
            prompt: "prompt",
            icon: "star",
            toolList: ["generate_task", "search_knowledge_bag"]
        )
        let inference = ChatOrchestratorInferenceOptions(
            useTools: false,
            useKnowledgeBag: true,
            useWebSearch: false,
            reasoningEnabled: false,
            reasoningEffortTier: 1
        )
        let modelAllowed: Set<String> = ["generate_task"]

        let output = SmallTaskCapabilityStrategy(smallTask: task).plan(
            ChatCapabilityStrategyInput(
                inference: inference,
                modelAllowedToolNames: modelAllowed,
                history: [makeUserMessage(text: "ignored")],
                threadID: UUID(),
                userQuestionForAI: "run task",
                hasHealthResourceContext: false
            )
        )

        XCTAssertEqual(output.inference.useTools, true)
        XCTAssertEqual(output.inference.useKnowledgeBag, true)
        XCTAssertEqual(output.inference.useWebSearch, false)
        XCTAssertEqual(output.inference.allowedToolNames, Set(["generate_task"]))
    }

    func testSmallTaskStrategyReplacesHistoryWithSyntheticUserMessage() {
        let task = SmallTask.createLocalTask(
            id: 2,
            name: "History Task",
            brief: "",
            prompt: "",
            icon: "star",
            toolList: []
        )
        let threadID = UUID()
        let priorHistory = [
            makeUserMessage(text: "old-1", threadID: threadID),
            makeUserMessage(text: "old-2", threadID: threadID),
        ]

        let output = SmallTaskCapabilityStrategy(smallTask: task).plan(
            ChatCapabilityStrategyInput(
                inference: .default,
                modelAllowedToolNames: nil,
                history: priorHistory,
                threadID: threadID,
                userQuestionForAI: "synthetic question",
                hasHealthResourceContext: false
            )
        )

        XCTAssertEqual(output.aiHistory.count, 1)
        XCTAssertEqual(output.aiHistory[0].threadID, threadID)
        XCTAssertEqual(output.aiHistory[0].role, .user)
        XCTAssertEqual(output.aiHistory[0].blocks.first?.text, "synthetic question")
        XCTAssertEqual(output.inference.useTools, false)
    }

    func testResolverSelectsSmallTaskStrategyWhenTaskPresent() {
        let task = SmallTask.createLocalTask(
            id: 3,
            name: "Resolver",
            brief: "",
            prompt: "",
            icon: "star",
            toolList: ["generate_task"]
        )
        let strategy = ChatCapabilityStrategyResolver.resolve(smallTask: task)
        XCTAssertEqual(strategy.name, "small_task")
    }

    func testResolverSelectsStandardChatStrategyWhenTaskAbsent() {
        let strategy = ChatCapabilityStrategyResolver.resolve(smallTask: nil)
        XCTAssertEqual(strategy.name, "chat")
    }

    func testReportInterpretationStrategyBehavesLikeStandardChat() {
        let flags = ChatComposerRuntimeFlags(
            useTools: true,
            useKnowledgeBag: true,
            useWebSearch: false,
            reasoningEnabled: false,
            reasoningEffortTier: 1
        )
        let inference = ChatOrchestratorInferenceOptions.from(composerFlags: flags)
        let history = [makeUserMessage(text: "report question")]
        let modelAllowed: Set<String> = ["get_health_resource_context"]
        let input = ChatCapabilityStrategyInput(
            inference: inference,
            modelAllowedToolNames: modelAllowed,
            history: history,
            threadID: history[0].threadID,
            userQuestionForAI: "report question",
            hasHealthResourceContext: true
        )

        let standard = StandardChatCapabilityStrategy().plan(input)
        let report = ReportInterpretationCapabilityStrategy().plan(input)

        XCTAssertEqual(report.inference, standard.inference)
        XCTAssertEqual(report.aiHistory, standard.aiHistory)
        XCTAssertEqual(ReportInterpretationCapabilityStrategy().name, "report_interpretation")
    }

    func testResolverPicksReportInterpretationWhenHealthResourceContextPresent() {
        let strategy = ChatCapabilityStrategyResolver.resolve(
            smallTask: nil,
            hasHealthResourceContext: true
        )
        XCTAssertEqual(strategy.name, "report_interpretation")
    }

    func testResolverPrefersSmallTaskOverReportInterpretation() {
        let task = SmallTask.createLocalTask(
            id: 4,
            name: "Priority",
            brief: "",
            prompt: "",
            icon: "star",
            toolList: ["generate_task"]
        )
        let strategy = ChatCapabilityStrategyResolver.resolve(
            smallTask: task,
            hasHealthResourceContext: true
        )
        XCTAssertEqual(strategy.name, "small_task")
    }

    private func makeUserMessage(text: String, threadID: UUID = UUID()) -> ChatMessage {
        ChatMessage(
            threadID: threadID,
            role: .user,
            blocks: [.init(kind: .text, text: text)],
            deliveryState: .pending,
            modelName: "user"
        )
    }
}
#endif
