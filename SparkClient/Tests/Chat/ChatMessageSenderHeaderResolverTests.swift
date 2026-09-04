#if canImport(XCTest)
import Foundation
import XCTest

final class ChatMessageSenderHeaderResolverTests: XCTestCase {
    func testRemoteSenderDTODecodesDoctorActorTypeFromSnakeCase() throws {
        let json = Data("""
        {
          "actor_type": "doctor",
          "actor_id": "doctor-37",
          "display_name": "开开 · 真人医生",
          "avatar_url": "https://cdn.example.test/kaikai.png",
          "title": "主任医师",
          "department_name": null,
          "source": "hospital_care"
        }
        """.utf8)
        let dto = try JSONDecoder.chatRemote.decode(ChatRemoteMessageSenderDTO.self, from: json)
        XCTAssertEqual(dto.actorType, "doctor")
        XCTAssertEqual(dto.actorId, "doctor-37")
        XCTAssertEqual(dto.displayName, "开开 · 真人医生")
        XCTAssertEqual(dto.avatarUrl, "https://cdn.example.test/kaikai.png")
    }

    func testSenderKindUsesServerSenderDoctorWithoutIntroCardInWindow() {
        let doctorMessage = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "开开 · 真人医生", actorId: "doctor-1")
        )
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: doctorMessage,
            scenarioModels: [makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")]
        )

        XCTAssertEqual(kind, .doctor(displayName: "开开", avatarURL: nil))
    }

    func testSenderKindUsesServerSenderAvatarURL() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: nil,
                sender: makeDoctorSender(
                    displayName: "李医生",
                    actorId: "doctor-1",
                    avatarURL: "https://cdn.example.test/li.png"
                )
            ),
            scenarioModels: []
        )
        XCTAssertEqual(kind, .doctor(displayName: "李医生", avatarURL: "https://cdn.example.test/li.png"))
    }

    // BACKOFFICE-HOSPITAL-AGENT-000002：医生智能体发言带头像时展示智能体头像头部。
    func testSenderKindShowsAgentAvatarForAIAgentWithAvatar() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: "qwen-plus",
                sender: makeAIAgentSenderWithAvatar("https://cdn.example.test/agent.webp?v=1")
            ),
            scenarioModels: [makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")]
        )
        XCTAssertEqual(kind, .aiAgent(displayName: "开开医生智能体", avatarURL: "https://cdn.example.test/agent.webp?v=1"))
    }

    func testSenderKindFallsBackToModelForAIAgentWithoutAvatar() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: "qwen-plus",
                sender: makeAIAgentSender()
            ),
            scenarioModels: [makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")]
        )
        XCTAssertEqual(kind, .aiModel(displayName: "Qwen-Plus", icon: .companyLogo(companyIconName(for: "QWEN"))))
    }

    func testSenderIdentityKeyUsesAgentKeyWhenAvatarPresent() {
        let message = makeAssistantMessage(
            modelName: "qwen-plus",
            sender: makeAIAgentSenderWithAvatar("https://cdn.example.test/agent.webp?v=1")
        )
        XCTAssertEqual(ChatMessageSenderHeaderResolver.senderIdentityKey(for: message), "agent:agent-37")
    }

    func testSenderKindTreatsBlankSenderAvatarAsNil() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: nil,
                sender: makeDoctorSender(displayName: "李医生", actorId: "doctor-1", avatarURL: "  ")
            ),
            scenarioModels: []
        )
        XCTAssertEqual(kind, .doctor(displayName: "李医生", avatarURL: nil))
    }

    func testSenderKindPrefersDoctorSenderOverModelName() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: "qwen-plus",
                sender: makeDoctorSender(displayName: "开开 · 真人医生", actorId: "doctor-1")
            ),
            scenarioModels: [makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")]
        )
        XCTAssertEqual(kind, .doctor(displayName: "开开", avatarURL: nil))
    }

    func testSenderKindDoesNotInferDoctorFromMissingSender() {
        XCTAssertNil(
            ChatMessageSenderHeaderResolver.senderKind(
                for: makeAssistantMessage(modelName: nil),
                scenarioModels: [makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")]
            )
        )
    }

    func testSenderKindKeepsAIModelWhenAIAgentSenderExists() {
        let row = makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(
                modelName: "qwen-plus",
                sender: makeAIAgentSender()
            ),
            scenarioModels: [row]
        )

        XCTAssertEqual(
            kind,
            .aiModel(displayName: "Qwen-Plus", icon: .companyLogo(companyIconName(for: "QWEN")))
        )
    }

    func testSenderKindFallsBackToModelNameWhenSenderMissing() {
        let row = makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(modelName: "qwen-plus"),
            scenarioModels: [row]
        )

        XCTAssertEqual(
            kind,
            .aiModel(displayName: "Qwen-Plus", icon: .companyLogo(companyIconName(for: "QWEN")))
        )
    }

    func testSenderKindResolvesCompanyLogoMatchingComposerPicker() {
        let row = makeModelRow(name: "qwen-plus", displayName: "Qwen-Plus", company: "QWEN")
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(modelName: "qwen-plus"),
            scenarioModels: [row]
        )
        XCTAssertEqual(
            kind,
            .aiModel(displayName: "Qwen-Plus", icon: .companyLogo(companyIconName(for: "QWEN")))
        )
    }

    func testSenderKindPrefersCustomSystemIconLikeComposerPicker() {
        let row = makeModelRow(
            name: "spark-agent",
            displayName: "小鲸助手",
            company: "HANLIN",
            icon: "person.crop.circle"
        )
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(modelName: "spark-agent"),
            scenarioModels: [row]
        )
        XCTAssertEqual(
            kind,
            .aiModel(displayName: "小鲸助手", icon: .systemName("person.crop.circle"))
        )
    }

    func testSenderKindFallsBackToModelNameWhenCatalogMisses() {
        let kind = ChatMessageSenderHeaderResolver.senderKind(
            for: makeAssistantMessage(modelName: "unknown-model"),
            scenarioModels: []
        )
        XCTAssertEqual(
            kind,
            .aiModel(displayName: "unknown-model", icon: .companyLogo(companyIconName(for: "")))
        )
    }

    func testSenderKindIgnoresUserAndEmptyModelName() {
        XCTAssertNil(
            ChatMessageSenderHeaderResolver.senderKind(
                for: makeAssistantMessage(modelName: "user"),
                scenarioModels: []
            )
        )
        XCTAssertNil(
            ChatMessageSenderHeaderResolver.senderKind(
                for: makeUserMessage(),
                scenarioModels: []
            )
        )
    }

    func testShouldShowHeaderOnFirstAssistantAndAfterUserTurn() {
        let first = makeAssistantMessage(modelName: "qwen-plus")
        let user = makeUserMessage()
        let second = makeAssistantMessage(modelName: "qwen-plus")
        let messages = [first, user, second]

        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: first, in: messages)
        )
        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: second, in: messages)
        )
    }

    func testShouldHideHeaderForConsecutiveSameModel() {
        let first = makeAssistantMessage(modelName: "qwen-plus")
        let second = makeAssistantMessage(modelName: "qwen-plus")
        let messages = [first, second]

        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: first, in: messages)
        )
        XCTAssertFalse(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: second, in: messages)
        )
    }

    func testShouldShowHeaderWhenModelChangesInConsecutiveAssistants() {
        let first = makeAssistantMessage(modelName: "qwen-plus")
        let second = makeAssistantMessage(modelName: "deepseek-chat")
        let messages = [first, second]

        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: second, in: messages)
        )
    }

    func testDoctorShowsHeaderOnEveryConsecutiveMessage() {
        let first = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "李医生", actorId: "doctor-1")
        )
        let second = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "李医生", actorId: "doctor-1")
        )
        let messages = [first, second]

        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: first, in: messages)
        )
        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: second, in: messages)
        )
    }

    func testHospitalConversationShowsModelThenDoctorHeaderWithoutIntroCardInWindow() {
        let row = makeModelRow(
            name: "agent-37-55-doubao-seed-2-1-pro-260628",
            displayName: "开开医生智能体",
            company: "DOUBAO"
        )
        let aiReply = makeAssistantMessage(
            modelName: "agent-37-55-doubao-seed-2-1-pro-260628",
            sender: makeAIAgentSender()
        )
        let doctorReply = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "开开 · 真人医生", actorId: "doctor-37")
        )
        let visibleWindow = [aiReply, doctorReply]

        XCTAssertEqual(
            ChatMessageSenderHeaderResolver.senderKind(for: aiReply, scenarioModels: [row]),
            .aiModel(
                displayName: "开开医生智能体",
                icon: .companyLogo(companyIconName(for: "DOUBAO"))
            )
        )
        XCTAssertEqual(
            ChatMessageSenderHeaderResolver.senderKind(for: doctorReply, scenarioModels: [row]),
            .doctor(displayName: "开开", avatarURL: nil)
        )
        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: aiReply, in: visibleWindow)
        )
        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: doctorReply, in: visibleWindow)
        )
    }

    func testHospitalConversationReshowsModelHeaderAfterDoctorThenAI() {
        let aiReply = makeAssistantMessage(modelName: "qwen-plus", sender: makeAIAgentSender())
        let doctorReply = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "开开 · 真人医生", actorId: "doctor-37")
        )
        let laterAIReply = makeAssistantMessage(modelName: "qwen-plus", sender: makeAIAgentSender())
        let messages = [aiReply, doctorReply, laterAIReply]

        XCTAssertTrue(
            ChatMessageSenderHeaderResolver.shouldShowSenderHeader(for: laterAIReply, in: messages)
        )
    }

    func testSurnameCharacterUsesFirstCharacter() {
        XCTAssertEqual(ChatMessageSenderHeaderResolver.surnameCharacter(from: "李医生"), "李")
        XCTAssertEqual(ChatMessageSenderHeaderResolver.surnameCharacter(from: "  "), "?")
    }

    func testDoctorShortDisplayNameStripsRealDoctorSuffix() {
        XCTAssertEqual(
            ChatMessageSenderHeaderResolver.doctorShortDisplayName(from: "开开 · 真人医生"),
            "开开"
        )
        XCTAssertEqual(
            ChatMessageSenderHeaderResolver.doctorShortDisplayName(from: "李医生"),
            "李医生"
        )
    }

    func testMergeEngineDoesNotSkipWhenRemoteAddsSender() {
        let local = makeAssistantMessage(modelName: nil)
        let remote = makeAssistantMessage(
            modelName: nil,
            sender: makeDoctorSender(displayName: "开开", actorId: "doctor-1")
        )
        XCTAssertFalse(
            ChatMergeEngine().shouldSkipApplyingRemote(local: local, remote: remote)
        )
        XCTAssertEqual(
            ChatMergeEngine().resolve(local: local, remote: remote).sender?.actorType,
            .doctor
        )
    }

    private func makeDoctorSender(
        displayName: String,
        actorId: String,
        avatarURL: String? = nil
    ) -> ChatMessageSender {
        ChatMessageSender(
            actorType: .doctor,
            actorId: actorId,
            displayName: displayName,
            avatarUrl: avatarURL,
            source: "hospital_care"
        )
    }

    private func makeAIAgentSender() -> ChatMessageSender {
        ChatMessageSender(
            actorType: .aiAgent,
            actorId: "agent-37",
            displayName: "开开医生智能体",
            source: "hospital_care"
        )
    }

    private func makeAIAgentSenderWithAvatar(_ avatarURL: String) -> ChatMessageSender {
        ChatMessageSender(
            actorType: .aiAgent,
            actorId: "agent-37",
            displayName: "开开医生智能体",
            avatarUrl: avatarURL,
            source: "hospital_care"
        )
    }

    private func makeAssistantMessage(
        modelName: String?,
        sender: ChatMessageSender? = nil
    ) -> ChatMessage {
        ChatMessage(
            threadID: threadID,
            role: .assistant,
            blocks: [ChatMessageBlock(kind: .text, text: "回复")],
            modelName: modelName,
            sender: sender
        )
    }

    private func makeUserMessage() -> ChatMessage {
        ChatMessage(
            threadID: threadID,
            role: .user,
            blocks: [ChatMessageBlock(kind: .text, text: "你好")],
            modelName: "user"
        )
    }

    private func makeModelRow(
        name: String,
        displayName: String,
        company: String,
        icon: String? = nil
    ) -> AIScenarioRemoteModelRow {
        AIScenarioRemoteModelRow(
            name: name,
            displayName: displayName,
            identity: AIModelIdentity.model.rawValue,
            company: company,
            endpoint: "https://local.example/v1/chat/completions",
            apiKey: nil,
            supportsSearch: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportsToolUse: false,
            supportsVoiceGen: false,
            supportsImageGen: false,
            supportsText: true,
            supportsDeepReasoning: false,
            reasoningControllable: false,
            priceTier: 1,
            systemProvision: nil,
            icon: icon,
            briefDescription: nil,
            source: "remote",
            aiScenarios: [AIScenario.chat.rawValue],
            aiToolScenarios: [],
            isDefault: false,
            temperature: 0.2,
            maxTokens: 2048
        )
    }

    private let threadID = UUID()
}
#endif
