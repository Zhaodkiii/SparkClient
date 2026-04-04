import Combine
import Foundation

@MainActor
final class MedicalUploadFlowViewModel: ObservableObject {
    enum Stage: Equatable {
        case picking
        case processing
        case result
    }

    struct ProgressStep: Identifiable, Equatable {
        enum State: Equatable {
            case waiting
            case running
            case done
            case failed
        }

        let id: String
        let title: String
        var state: State
    }

    @Published private(set) var stage: Stage = .picking
    @Published private(set) var progressSteps: [ProgressStep] = []
    @Published private(set) var draft: RecognizedMedicalDraft?
    @Published private(set) var selectedMemberName: String?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let patientContextStore: PatientContextStore
    private let extractMedicalDraftFromDocumentUseCase: ExtractMedicalDraftFromDocumentUseCase
    private let confirmMedicalDraftUseCase: ConfirmMedicalDraftUseCase
    private let logger: Logger

    init(
        patientContextStore: PatientContextStore,
        extractMedicalDraftFromDocumentUseCase: ExtractMedicalDraftFromDocumentUseCase,
        confirmMedicalDraftUseCase: ConfirmMedicalDraftUseCase,
        logger: Logger = ConsoleLogger()
    ) {
        self.patientContextStore = patientContextStore
        self.extractMedicalDraftFromDocumentUseCase = extractMedicalDraftFromDocumentUseCase
        self.confirmMedicalDraftUseCase = confirmMedicalDraftUseCase
        self.logger = logger
        self.selectedMemberName = patientContextStore.context.selectedMember?.name
    }

    func beginRecognition(filePath: String) async {
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.no_member")
            return
        }

        selectedMemberName = member.name
        stage = .processing
        draft = nil
        errorMessage = nil
        progressSteps = [
            ProgressStep(id: "upload", title: L10n.text("medical.upload.step.prepare_file"), state: .running),
            ProgressStep(id: "ocr", title: L10n.text("medical.upload.step.ocr"), state: .waiting),
            ProgressStep(id: "extract", title: L10n.text("medical.upload.step.extract"), state: .waiting)
        ]

        do {
            markDone("upload")
            markRunning("ocr")

            let extracted = try await extractMedicalDraftFromDocumentUseCase.execute(
                patientID: member.id,
                filePath: filePath
            )

            markDone("ocr")
            markRunning("extract")
            markDone("extract")

            draft = extracted
            stage = .result
        } catch {
            markFailedCurrent()
            logger.error("医疗抽取失败: \(error.localizedDescription)", category: "medical_upload")
            errorMessage = error.localizedDescription
        }
    }

    func confirmDraft() async -> Bool {
        guard isSaving == false else { return false }
        guard let member = patientContextStore.context.selectedMember else {
            errorMessage = L10n.text("medical.upload.error.member_invalid")
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await confirmMedicalDraftUseCase.execute(patientID: member.id)
            reset()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        stage = .picking
        progressSteps = []
        draft = nil
        errorMessage = nil
        selectedMemberName = patientContextStore.context.selectedMember?.name
    }

    private func markRunning(_ id: String) {
        update(id) { $0.state = .running }
    }

    private func markDone(_ id: String) {
        update(id) { $0.state = .done }
    }

    private func markFailedCurrent() {
        guard let running = progressSteps.first(where: { $0.state == .running }) else { return }
        update(running.id) { $0.state = .failed }
    }

    private func update(_ id: String, transform: (inout ProgressStep) -> Void) {
        guard let index = progressSteps.firstIndex(where: { $0.id == id }) else { return }
        var copy = progressSteps[index]
        transform(&copy)
        progressSteps[index] = copy
    }
}

#if DEBUG
private struct PreviewMedicalRuntimeService: AIRuntimeServing {
    func generateText(request _: AIRuntimeTextRequest) async throws -> AIRuntimeTextResponse {
        AIRuntimeTextResponse(
            text: """
            {"title":"门诊复查记录","summary":"患者主诉咽痛三天，体温正常。","diagnosis":"上呼吸道感染","occurredAt":"2026-04-01"}
            """,
            model: "preview",
            promptTokens: nil,
            completionTokens: nil
        )
    }
}

private actor PreviewMedicalDataRepository: MedicalDataRepository {
    private var snapshot = MedicalDataSnapshot(
        members: [],
        medicalCases: [],
        examinationReports: [],
        medicalReports: [],
        prescriptions: [],
        healthMetrics: [],
        updatedAt: Date()
    )

    func loadSnapshot() async -> MedicalDataSnapshot {
        snapshot
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        self.snapshot = snapshot
    }

    func uploadSnapshotToServer(priority _: CloudSyncPriority) async throws {}

    func pullSnapshotFromServer(priority _: CloudSyncPriority) async throws {}
}

extension MedicalUploadFlowViewModel {
    static func preview() -> MedicalUploadFlowViewModel {
        let patientStore = PatientContextStore()
        let member = Member(name: "本人", relationship: "self", isPrimary: true)
        patientStore.update(members: [member], selectedMemberID: member.id)

        return MedicalUploadFlowViewModel(
            patientContextStore: patientStore,
            extractMedicalDraftFromDocumentUseCase: ExtractMedicalDraftFromDocumentUseCase(
                ocrOrchestrator: OCROrchestrator(config: OCRConfiguration()),
                runtimeService: PreviewMedicalRuntimeService(),
                draftRepository: InMemoryMedicalDraftRepository()
            ),
            confirmMedicalDraftUseCase: ConfirmMedicalDraftUseCase(
                draftRepository: InMemoryMedicalDraftRepository(),
                medicalDataRepository: PreviewMedicalDataRepository()
            )
        )
    }
}
#endif
