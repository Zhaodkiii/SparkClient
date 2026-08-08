import Foundation

/// DeepTutor 消息块类型（独立于 Chat `ChatMessageBlockKind`）。
nonisolated enum DeepTutorMessageBlockKind: String, Codable, Sendable {
    case envelope
    case text
    case thinking
    case trace
    case askUser
    case captureCard
    case memberSelection
    case memberProfile
    case generatedFile
    case researchOutline
    case quiz
    case quizParseError
    case visualization
    case error
}

nonisolated enum DeepTutorMessageStatus: String, Codable, Sendable {
    case draft
    case pending
    case streaming
    case ready
    case failed
    case deleted
}

nonisolated enum DeepTutorMessageBlockPayload: Codable, Equatable, Sendable {
    case envelope(DeepTutorMessageEnvelope)
    case text(String)
    case thinking(String)
    case trace(DeepTutorTraceBlockPayload)
    case askUser(DeepTutorAskUserBlockPayload)
    case captureCard(DeepTutorCaptureCardPayload)
    case memberSelection(DeepTutorMemberSelectionBlockPayload)
    case memberProfile(DeepTutorMemberProfileBlockPayload)
    case generatedFile(DeepTutorGeneratedFilePayload)
    case researchOutline(DeepTutorResearchOutlinePayload)
    case quiz(DeepTutorQuizPayload)
    case quizParseError(DeepTutorQuizParseErrorPayload)
    case visualization(DeepTutorVisualizationPayload)
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case envelope
        case text
        case thinking
        case trace
        case askUser
        case captureCard
        case memberSelection
        case memberProfile
        case generatedFile
        case researchOutline
        case quiz
        case quizParseError
        case visualization
        case error
    }

    private enum PayloadType: String, Codable {
        case envelope
        case text
        case thinking
        case trace
        case askUser
        case captureCard
        case memberSelection
        case memberProfile
        case generatedFile
        case researchOutline
        case quiz
        case quizParseError
        case visualization
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .envelope:
            self = .envelope(try container.decode(DeepTutorMessageEnvelope.self, forKey: .envelope))
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .thinking:
            self = .thinking(try container.decode(String.self, forKey: .thinking))
        case .trace:
            self = .trace(try container.decode(DeepTutorTraceBlockPayload.self, forKey: .trace))
        case .askUser:
            self = .askUser(try container.decode(DeepTutorAskUserBlockPayload.self, forKey: .askUser))
        case .captureCard:
            self = .captureCard(try container.decode(DeepTutorCaptureCardPayload.self, forKey: .captureCard))
        case .memberSelection:
            self = .memberSelection(try container.decode(DeepTutorMemberSelectionBlockPayload.self, forKey: .memberSelection))
        case .memberProfile:
            self = .memberProfile(try container.decode(DeepTutorMemberProfileBlockPayload.self, forKey: .memberProfile))
        case .generatedFile:
            self = .generatedFile(try container.decode(DeepTutorGeneratedFilePayload.self, forKey: .generatedFile))
        case .researchOutline:
            self = .researchOutline(try container.decode(DeepTutorResearchOutlinePayload.self, forKey: .researchOutline))
        case .quiz:
            self = .quiz(try container.decode(DeepTutorQuizPayload.self, forKey: .quiz))
        case .quizParseError:
            self = .quizParseError(try container.decode(DeepTutorQuizParseErrorPayload.self, forKey: .quizParseError))
        case .visualization:
            self = .visualization(try container.decode(DeepTutorVisualizationPayload.self, forKey: .visualization))
        case .error:
            self = .error(try container.decode(String.self, forKey: .error))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .envelope(let value):
            try container.encode(PayloadType.envelope, forKey: .type)
            try container.encode(value, forKey: .envelope)
        case .text(let value):
            try container.encode(PayloadType.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .thinking(let value):
            try container.encode(PayloadType.thinking, forKey: .type)
            try container.encode(value, forKey: .thinking)
        case .trace(let value):
            try container.encode(PayloadType.trace, forKey: .type)
            try container.encode(value, forKey: .trace)
        case .askUser(let value):
            try container.encode(PayloadType.askUser, forKey: .type)
            try container.encode(value, forKey: .askUser)
        case .captureCard(let value):
            try container.encode(PayloadType.captureCard, forKey: .type)
            try container.encode(value, forKey: .captureCard)
        case .memberSelection(let value):
            try container.encode(PayloadType.memberSelection, forKey: .type)
            try container.encode(value, forKey: .memberSelection)
        case .memberProfile(let value):
            try container.encode(PayloadType.memberProfile, forKey: .type)
            try container.encode(value, forKey: .memberProfile)
        case .generatedFile(let value):
            try container.encode(PayloadType.generatedFile, forKey: .type)
            try container.encode(value, forKey: .generatedFile)
        case .researchOutline(let value):
            try container.encode(PayloadType.researchOutline, forKey: .type)
            try container.encode(value, forKey: .researchOutline)
        case .quiz(let value):
            try container.encode(PayloadType.quiz, forKey: .type)
            try container.encode(value, forKey: .quiz)
        case .quizParseError(let value):
            try container.encode(PayloadType.quizParseError, forKey: .type)
            try container.encode(value, forKey: .quizParseError)
        case .visualization(let value):
            try container.encode(PayloadType.visualization, forKey: .type)
            try container.encode(value, forKey: .visualization)
        case .error(let value):
            try container.encode(PayloadType.error, forKey: .type)
            try container.encode(value, forKey: .error)
        }
    }
}

nonisolated struct DeepTutorMessageEnvelope: Codable, Equatable, Sendable {
    var serverID: String?
    var capability: DeepTutorCapability
    var events: [DeepTutorStreamEvent]
    var attachments: [DeepTutorAttachment]
    var requestSnapshot: DeepTutorRequestSnapshot?
    var parentMessageID: UUID?
    var status: DeepTutorMessageStatus
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case serverID
        case capability
        case events
        case attachments
        case requestSnapshot
        case parentMessageID
        case status
        case updatedAt
    }

    init(
        serverID: String?,
        capability: DeepTutorCapability,
        events: [DeepTutorStreamEvent],
        attachments: [DeepTutorAttachment],
        requestSnapshot: DeepTutorRequestSnapshot?,
        parentMessageID: UUID?,
        status: DeepTutorMessageStatus,
        updatedAt: Date
    ) {
        self.serverID = serverID
        self.capability = capability
        self.events = events
        self.attachments = attachments
        self.requestSnapshot = requestSnapshot
        self.parentMessageID = parentMessageID
        self.status = status
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverID = try container.decodeIfPresent(String.self, forKey: .serverID)
        capability = try container.decode(DeepTutorCapability.self, forKey: .capability)
        events = DeepTutorStreamEventCompatibility.decodeLossyArray(from: container, forKey: .events)
        attachments = try container.decodeIfPresent([DeepTutorAttachment].self, forKey: .attachments) ?? []
        requestSnapshot = try container.decodeIfPresent(DeepTutorRequestSnapshot.self, forKey: .requestSnapshot)
        parentMessageID = try container.decodeIfPresent(UUID.self, forKey: .parentMessageID)
        status = try container.decode(DeepTutorMessageStatus.self, forKey: .status)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

nonisolated struct DeepTutorMessageBlock: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: DeepTutorMessageBlockKind
    let payload: DeepTutorMessageBlockPayload
    let toolCallID: String?
    let revision: Int64
    let orderKey: Double
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        kind: DeepTutorMessageBlockKind,
        payload: DeepTutorMessageBlockPayload,
        toolCallID: String? = nil,
        revision: Int64 = 0,
        orderKey: Double,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.toolCallID = toolCallID
        self.revision = revision
        self.orderKey = orderKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct DeepTutorTraceBlockPayload: Codable, Equatable, Sendable {
    var title: String
    var rows: [DeepTutorTraceRowModel]
    var isExpanded: Bool
    var isStreaming: Bool
    var isFinalAnswerPhase: Bool
    var elapsedSeconds: Double?

    init(
        title: String,
        rows: [DeepTutorTraceRowModel],
        isExpanded: Bool,
        isStreaming: Bool = false,
        isFinalAnswerPhase: Bool = false,
        elapsedSeconds: Double? = nil
    ) {
        self.title = title
        self.rows = rows
        self.isExpanded = isExpanded
        self.isStreaming = isStreaming
        self.isFinalAnswerPhase = isFinalAnswerPhase
        self.elapsedSeconds = elapsedSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        rows = try container.decode([DeepTutorTraceRowModel].self, forKey: .rows)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        isFinalAnswerPhase = try container.decodeIfPresent(Bool.self, forKey: .isFinalAnswerPhase) ?? false
        elapsedSeconds = try container.decodeIfPresent(Double.self, forKey: .elapsedSeconds)
    }
}

nonisolated enum DeepTutorTraceRowKind: String, Codable, Sendable {
    case thinking
    case tool
    case askUser
    case error
}

nonisolated struct DeepTutorTraceRowModel: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: DeepTutorTraceRowKind
    var icon: String
    var verb: String
    var chip: String?
    var status: DeepTutorTraceRowStatus
    var toolName: String?
    var chipIsMonospaced: Bool
    var durationSeconds: Double?
    var argsDetail: String?
    var resultDetail: String?
    var resultIsMarkdown: Bool

    init(
        id: String,
        kind: DeepTutorTraceRowKind = .tool,
        icon: String,
        verb: String,
        chip: String? = nil,
        status: DeepTutorTraceRowStatus,
        toolName: String? = nil,
        chipIsMonospaced: Bool = false,
        durationSeconds: Double? = nil,
        argsDetail: String? = nil,
        resultDetail: String? = nil,
        resultIsMarkdown: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.icon = icon
        self.verb = verb
        self.chip = chip
        self.status = status
        self.toolName = toolName
        self.chipIsMonospaced = chipIsMonospaced
        self.durationSeconds = durationSeconds
        self.argsDetail = argsDetail
        self.resultDetail = resultDetail
        self.resultIsMarkdown = resultIsMarkdown
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, icon, verb, chip, status, toolName, chipIsMonospaced
        case durationSeconds, argsDetail, resultDetail, resultIsMarkdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(DeepTutorTraceRowKind.self, forKey: .kind)
        icon = try container.decode(String.self, forKey: .icon)
        verb = try container.decode(String.self, forKey: .verb)
        chip = try container.decodeIfPresent(String.self, forKey: .chip)
        status = try container.decode(DeepTutorTraceRowStatus.self, forKey: .status)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        chipIsMonospaced = try container.decodeIfPresent(Bool.self, forKey: .chipIsMonospaced) ?? false
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        argsDetail = try container.decodeIfPresent(String.self, forKey: .argsDetail)
        resultDetail = try container.decodeIfPresent(String.self, forKey: .resultDetail)
        resultIsMarkdown = try container.decodeIfPresent(Bool.self, forKey: .resultIsMarkdown) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(icon, forKey: .icon)
        try container.encode(verb, forKey: .verb)
        try container.encodeIfPresent(chip, forKey: .chip)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(chipIsMonospaced, forKey: .chipIsMonospaced)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(argsDetail, forKey: .argsDetail)
        try container.encodeIfPresent(resultDetail, forKey: .resultDetail)
        try container.encode(resultIsMarkdown, forKey: .resultIsMarkdown)
    }
}

nonisolated enum DeepTutorTraceRowStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
}

nonisolated struct DeepTutorAskUserBlockPayload: Codable, Equatable, Sendable {
    var payload: DeepTutorAskUserPayload
    var toolCallID: String
    var isResolved: Bool
    var answers: [DeepTutorAskUserAnswer]

    enum CodingKeys: String, CodingKey {
        case payload
        case toolCallID
        case tool_call_id
        case isResolved
        case answers
    }

    init(
        payload: DeepTutorAskUserPayload,
        toolCallID: String,
        isResolved: Bool,
        answers: [DeepTutorAskUserAnswer]
    ) {
        self.payload = payload
        self.toolCallID = toolCallID
        self.isResolved = isResolved
        self.answers = answers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payload = try container.decode(DeepTutorAskUserPayload.self, forKey: .payload)
        toolCallID = Self.decodeToolCallID(from: container)
        isResolved = try container.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
        answers = try container.decodeIfPresent([DeepTutorAskUserAnswer].self, forKey: .answers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
        try container.encode(toolCallID, forKey: .toolCallID)
        try container.encode(isResolved, forKey: .isResolved)
        try container.encode(answers, forKey: .answers)
    }

    private static func decodeToolCallID(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        for key in [CodingKeys.toolCallID, .tool_call_id] {
            if let value = try? container.decode(String.self, forKey: key),
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
        }
        return ""
    }
}

nonisolated struct DeepTutorMemberSelectionBlockPayload: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case running
        case completed
        case timeout
        case cancelled
        case expired
    }

    var toolCallID: String
    var toolName: String
    var reason: String
    var arguments: [String: String]
    var selectedMemberID: Int?
    var selectedMemberName: String?
    var status: Status
    var resultText: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case toolCallID
        case tool_call_id
        case toolName
        case tool_name
        case reason
        case arguments
        case selectedMemberID
        case selected_member_id
        case selectedMemberName
        case selected_member_name
        case status
        case resultText
        case result_text
        case createdAt
        case created_at
        case updatedAt
        case updated_at
    }

    var isResolved: Bool {
        status == .completed
    }

    init(
        toolCallID: String,
        toolName: String = SparkToolName.requestMemberSelection.rawValue,
        reason: String,
        arguments: [String: String] = [:],
        selectedMemberID: Int? = nil,
        selectedMemberName: String? = nil,
        status: Status = .pending,
        resultText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.reason = reason
        self.arguments = arguments
        self.selectedMemberID = selectedMemberID
        self.selectedMemberName = selectedMemberName
        self.status = status
        self.resultText = resultText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallID = Self.decodeString(from: container, keys: [.toolCallID, .tool_call_id]) ?? ""
        toolName = Self.decodeString(from: container, keys: [.toolName, .tool_name]) ?? SparkToolName.requestMemberSelection.rawValue
        reason = Self.decodeString(from: container, keys: [.reason]) ?? "需要先确认本次对话对应的家庭成员。"
        arguments = (try? container.decodeIfPresent([String: String].self, forKey: .arguments)) ?? [:]
        selectedMemberID = Self.decodeInt(from: container, keys: [.selectedMemberID, .selected_member_id])
        selectedMemberName = Self.decodeString(from: container, keys: [.selectedMemberName, .selected_member_name])
        status = (try? container.decodeIfPresent(Status.self, forKey: .status)) ?? (selectedMemberID == nil ? .pending : .completed)
        resultText = Self.decodeString(from: container, keys: [.resultText, .result_text])
        let now = Date()
        createdAt = Self.decodeDate(from: container, keys: [.createdAt, .created_at]) ?? now
        updatedAt = Self.decodeDate(from: container, keys: [.updatedAt, .updated_at]) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolCallID, forKey: .toolCallID)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(reason, forKey: .reason)
        try container.encode(arguments, forKey: .arguments)
        try container.encodeIfPresent(selectedMemberID, forKey: .selectedMemberID)
        try container.encodeIfPresent(selectedMemberName, forKey: .selectedMemberName)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(resultText, forKey: .resultText)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func decodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return value
            }
        }
        return nil
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeIfPresent(String.self, forKey: key),
               let intValue = Int(value) {
                return intValue
            }
        }
        return nil
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Date? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Date.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}

nonisolated struct DeepTutorMemberProfileSectionCardPayload: Codable, Equatable, Sendable, Identifiable {
    var sectionCode: String
    var title: String
    var summary: String
    var status: String

    var id: String { sectionCode }
}

nonisolated struct DeepTutorMemberProfileBlockPayload: Codable, Equatable, Sendable {
    var toolCallID: String
    var memberID: Int
    var memberName: String
    var relationshipText: String
    var genderText: String
    var ageText: String
    var bodyMetricsSummary: String
    var requestedFocus: String?
    var basicProfileSummary: String
    var healthHistorySummary: String
    var lifestyleSummary: String
    var examArchiveSummary: String
    var riskAssessmentSummary: String
    var sections: [DeepTutorMemberProfileSectionCardPayload]
    var medicalCaseCount: Int
    var symptomCount: Int
    var surgeryCount: Int
    var followUpCount: Int
    var healthExamReportCount: Int
    var examinationReportCount: Int
    var medicationPlanCount: Int
    var guidanceUpdatedAt: Date?
    var source: String
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct DeepTutorGeneratedFilePayload: Codable, Equatable, Sendable {
    var filename: String
    var mimeType: String?
    var localPath: String?
    var previewURL: String?
    var sizeBytes: Int64?
    var generated: Bool
}

nonisolated struct DeepTutorResearchOutlinePayload: Codable, Equatable, Sendable {
    var title: String
    var sections: [DeepTutorResearchOutlineSection]
    var followupMessageID: UUID?
}

nonisolated struct DeepTutorResearchOutlineSection: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var summary: String?
}

nonisolated struct DeepTutorVisualizationPayload: Codable, Equatable, Sendable {
    var title: String
    var snapshotDescription: String
    var placeholderKind: String
}

nonisolated struct DeepTutorAttachment: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var type: String
    var filename: String?
    var mimeType: String?
    var localPath: String?
    var previewURL: String?
    var generated: Bool
    var fileId: Int64?
    var fileUuid: String?
    var objectKey: String?
    var fullCacheKey: String?
    var fileMd5: String?
    var byteCount: Int?
    var aiByteCount: Int?

    init(
        id: String,
        type: String,
        filename: String? = nil,
        mimeType: String? = nil,
        localPath: String? = nil,
        previewURL: String? = nil,
        generated: Bool = false,
        fileId: Int64? = nil,
        fileUuid: String? = nil,
        objectKey: String? = nil,
        fullCacheKey: String? = nil,
        fileMd5: String? = nil,
        byteCount: Int? = nil,
        aiByteCount: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.filename = filename
        self.mimeType = mimeType
        self.localPath = localPath
        self.previewURL = previewURL
        self.generated = generated
        self.fileId = fileId
        self.fileUuid = fileUuid
        self.objectKey = objectKey
        self.fullCacheKey = fullCacheKey
        self.fileMd5 = fileMd5
        self.byteCount = byteCount
        self.aiByteCount = aiByteCount
    }

    var resolvedRemoteURL: URL? {
        previewURL.flatMap(URL.init(string:))
    }

    func sparkClientOSSFileUUIDAndFileName() -> (fileUUID: String, fileName: String)? {
        if let fullCacheKey {
            let parts = fullCacheKey.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return (parts[0], parts[1])
            }
        }
        if let fileUuid, let filename {
            return (fileUuid.lowercased(), filename)
        }
        return nil
    }

    func managedFileRecord(downloadURL: URL?) -> ManagedFileRecord? {
        guard let fileUuid, let filename else { return nil }
        let resolvedURL = downloadURL ?? resolvedRemoteURL
        return ManagedFileRecord(
            id: Int(fileId ?? 0),
            fileUuid: fileUuid,
            filePath: resolvedURL?.absoluteString,
            originalName: filename,
            fileSize: byteCount ?? 0,
            mimeType: mimeType ?? "application/octet-stream",
            fileMd5: fileMd5,
            isPublic: false,
            businessType: DeepTutorSendAttachmentAssembly.businessType,
            businessId: id,
            createdAt: "",
            objectKey: objectKey,
            storageType: "oss"
        )
    }

    func toChatAttachment() -> ChatAttachment? {
        let attachmentID = UUID(uuidString: id) ?? UUID()
        let attachmentType: ChatAttachmentType = switch type {
        case "image": .image
        case "pdf": .pdf
        default: .file
        }
        return ChatAttachment(
            id: attachmentID,
            type: attachmentType,
            url: resolvedRemoteURL,
            text: nil,
            fileId: fileId.map(Int.init),
            fullCacheKey: fullCacheKey,
            fileMd5: fileMd5
        )
    }
}

nonisolated struct DeepTutorRequestSnapshot: Codable, Equatable, Sendable {
    var references: [DeepTutorContextReference]
    var capability: DeepTutorCapability?
    var enabledTools: [String]?
    var toolSnapshot: DeepTutorPerTurnToolSnapshot?
    var attachments: [DeepTutorAttachment]
    var searchConfigRevision: SearchRuntimeConfigRevision?
    var selectedModelName: String?
    var selectedModelIdentity: String?
    var selectedAgentBaseModelName: String?
    var modelAllowedToolNames: [String]?
    var finalAllowedToolNames: [String]?
    var promptSource: String?
    var resolvedTemperature: Double?
    var resolvedMaxTokens: Int?
    var turnID: UUID?
    var resumeMode: String?
    var capabilityStage: String?
    var modelResolutionMode: String?

    init(
        references: [DeepTutorContextReference] = [],
        capability: DeepTutorCapability? = nil,
        enabledTools: [String]? = nil,
        toolSnapshot: DeepTutorPerTurnToolSnapshot? = nil,
        attachments: [DeepTutorAttachment] = [],
        searchConfigRevision: SearchRuntimeConfigRevision? = nil,
        selectedModelName: String? = nil,
        selectedModelIdentity: String? = nil,
        selectedAgentBaseModelName: String? = nil,
        modelAllowedToolNames: [String]? = nil,
        finalAllowedToolNames: [String]? = nil,
        promptSource: String? = nil,
        resolvedTemperature: Double? = nil,
        resolvedMaxTokens: Int? = nil,
        turnID: UUID? = nil,
        resumeMode: String? = nil,
        capabilityStage: String? = nil,
        modelResolutionMode: String? = nil
    ) {
        self.references = references
        self.capability = capability
        self.enabledTools = enabledTools
        self.toolSnapshot = toolSnapshot
        self.attachments = attachments
        self.searchConfigRevision = searchConfigRevision
        self.selectedModelName = selectedModelName
        self.selectedModelIdentity = selectedModelIdentity
        self.selectedAgentBaseModelName = selectedAgentBaseModelName
        self.modelAllowedToolNames = modelAllowedToolNames
        self.finalAllowedToolNames = finalAllowedToolNames
        self.promptSource = promptSource
        self.resolvedTemperature = resolvedTemperature
        self.resolvedMaxTokens = resolvedMaxTokens
        self.turnID = turnID
        self.resumeMode = resumeMode
        self.capabilityStage = capabilityStage
        self.modelResolutionMode = modelResolutionMode
    }

    enum CodingKeys: String, CodingKey {
        case references, capability, enabledTools, toolSnapshot, attachments, searchConfigRevision
        case selectedModelName, selectedModelIdentity, selectedAgentBaseModelName
        case modelAllowedToolNames, finalAllowedToolNames, promptSource
        case resolvedTemperature, resolvedMaxTokens
        case turnID, resumeMode, capabilityStage, modelResolutionMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        references = try container.decodeIfPresent([DeepTutorContextReference].self, forKey: .references) ?? []
        capability = try container.decodeIfPresent(DeepTutorCapability.self, forKey: .capability)
        enabledTools = try container.decodeIfPresent([String].self, forKey: .enabledTools)
        toolSnapshot = try container.decodeIfPresent(DeepTutorPerTurnToolSnapshot.self, forKey: .toolSnapshot)
        attachments = try container.decodeIfPresent([DeepTutorAttachment].self, forKey: .attachments) ?? []
        searchConfigRevision = try container.decodeIfPresent(SearchRuntimeConfigRevision.self, forKey: .searchConfigRevision)
        selectedModelName = try container.decodeIfPresent(String.self, forKey: .selectedModelName)
        selectedModelIdentity = try container.decodeIfPresent(String.self, forKey: .selectedModelIdentity)
        selectedAgentBaseModelName = try container.decodeIfPresent(String.self, forKey: .selectedAgentBaseModelName)
        modelAllowedToolNames = try container.decodeIfPresent([String].self, forKey: .modelAllowedToolNames)
        finalAllowedToolNames = try container.decodeIfPresent([String].self, forKey: .finalAllowedToolNames)
        promptSource = try container.decodeIfPresent(String.self, forKey: .promptSource)
        resolvedTemperature = try container.decodeIfPresent(Double.self, forKey: .resolvedTemperature)
        resolvedMaxTokens = try container.decodeIfPresent(Int.self, forKey: .resolvedMaxTokens)
        turnID = try container.decodeIfPresent(UUID.self, forKey: .turnID)
        resumeMode = try container.decodeIfPresent(String.self, forKey: .resumeMode)
        capabilityStage = try container.decodeIfPresent(String.self, forKey: .capabilityStage)
        modelResolutionMode = try container.decodeIfPresent(String.self, forKey: .modelResolutionMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(references, forKey: .references)
        try container.encodeIfPresent(capability, forKey: .capability)
        try container.encodeIfPresent(enabledTools, forKey: .enabledTools)
        try container.encodeIfPresent(toolSnapshot, forKey: .toolSnapshot)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(searchConfigRevision, forKey: .searchConfigRevision)
        try container.encodeIfPresent(selectedModelName, forKey: .selectedModelName)
        try container.encodeIfPresent(selectedModelIdentity, forKey: .selectedModelIdentity)
        try container.encodeIfPresent(selectedAgentBaseModelName, forKey: .selectedAgentBaseModelName)
        try container.encodeIfPresent(modelAllowedToolNames, forKey: .modelAllowedToolNames)
        try container.encodeIfPresent(finalAllowedToolNames, forKey: .finalAllowedToolNames)
        try container.encodeIfPresent(promptSource, forKey: .promptSource)
        try container.encodeIfPresent(resolvedTemperature, forKey: .resolvedTemperature)
        try container.encodeIfPresent(resolvedMaxTokens, forKey: .resolvedMaxTokens)
        try container.encodeIfPresent(turnID, forKey: .turnID)
        try container.encodeIfPresent(resumeMode, forKey: .resumeMode)
        try container.encodeIfPresent(capabilityStage, forKey: .capabilityStage)
        try container.encodeIfPresent(modelResolutionMode, forKey: .modelResolutionMode)
    }
}

nonisolated struct DeepTutorContextReference: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var subtitle: String?
}
