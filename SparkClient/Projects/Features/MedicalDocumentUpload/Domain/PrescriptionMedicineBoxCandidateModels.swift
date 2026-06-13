import Foundation

/// 处方识别结果中某个药品候选药盒的稳定定位键。
struct MedicationCandidateKey: Hashable, Sendable {
    /// 所属处方批次在当前识别结果列表中的索引。
    let prescriptionIndex: Int
    /// 药品计划在处方批次中的索引。
    let medicationIndex: Int
}

/// 药盒候选与家庭已有药盒之间的匹配结果。
enum MedicineBoxCandidateMatch: Equatable, Sendable {
    /// 当前药品没有可用于创建或绑定药盒的候选信息。
    case noCandidate
    /// 有候选药盒信息，但家庭药盒列表中没有同名药盒。
    case noExisting(candidate: MedicineBoxRecognitionDraft)
    /// 唯一匹配到一个已有药盒，可直接绑定。
    case uniqueExisting(candidate: MedicineBoxRecognitionDraft, target: SparkMedicalSyncAPI.RemoteMedicineBox)
    /// 匹配到多个同名已有药盒，需要用户选择具体绑定目标。
    case multipleExisting(candidate: MedicineBoxRecognitionDraft, targets: [SparkMedicalSyncAPI.RemoteMedicineBox])
    /// 加载家庭药盒列表失败，暂时无法判断是否存在匹配项。
    case loadFailed(candidate: MedicineBoxRecognitionDraft, message: String)
}

/// 用户对药盒候选的最终处理方式。
enum MedicineBoxCandidateAction: Equatable, Sendable {
    /// 尚未选择处理动作。
    case none
    /// 绑定到一个已有药盒。
    case bindExisting(medicineBoxID: Int)
    /// 使用候选信息创建新药盒。
    case createNew
}

/// 用户对单个药盒候选的确认状态和编辑结果。
struct MedicineBoxCandidateConfirmation: Equatable, Sendable {
    /// 用户是否已经确认该候选的处理方式。
    var isConfirmed: Bool
    /// 确认后要执行的药盒处理动作。
    var action: MedicineBoxCandidateAction
    /// 用户编辑后的候选药盒信息；为空时使用识别出的原始候选。
    var editedCandidate: MedicineBoxRecognitionDraft?
    /// 在多个已有药盒命中时，用户选择绑定的药盒 ID。
    var selectedExistingBoxID: Int?

    /// 默认的未确认状态。
    static let `default` = MedicineBoxCandidateConfirmation(
        isConfirmed: false,
        action: .none,
        editedCandidate: nil,
        selectedExistingBoxID: nil
    )
}

/// 药盒候选确认页顶部概览所需的统计数据。
struct PrescriptionMedicineBoxOverviewStats: Equatable, Sendable {
    /// 当前识别出的处方批次数量。
    let prescriptionCount: Int
    /// 所有处方批次中的药品计划总数。
    let medicationCount: Int
    /// 可处理的药盒候选总数。
    let candidateCount: Int
    /// 仍需要用户确认或补选的候选数量。
    let pendingCount: Int
    /// 已经可以绑定到已有药盒的候选数量。
    let matchedExistingCount: Int
    /// 需要创建新药盒的候选数量。
    let createNewCount: Int
}

/// 药盒候选匹配和统计的纯逻辑工具。
enum PrescriptionMedicineBoxCandidateMatcher {
    /// 将药品名称归一化，用于跨全半角、空白和大小写差异进行匹配。
    static func normalizeMedicineName(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        value = value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
        value = value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return value.lowercased()
    }

    /// 获取用于匹配的候选药品名称，优先使用用户编辑后的候选信息。
    static func candidateName(
        for plan: MedicationPlanRecognitionDraft,
        editedCandidate: MedicineBoxRecognitionDraft?
    ) -> String? {
        if let editedCandidate {
            return editedCandidate.medicineName?.nilIfBlank
                ?? editedCandidate.brandName?.nilIfBlank
        }
        if let box = plan.medicineBox {
            return box.medicineName?.nilIfBlank
                ?? plan.medicineName?.nilIfBlank
                ?? box.brandName?.nilIfBlank
        }
        return plan.medicineName?.nilIfBlank
    }

    /// 返回当前真正生效的候选药盒；如果药品被标记为不关联药盒，则返回空。
    static func effectiveCandidate(
        for plan: MedicationPlanRecognitionDraft,
        confirmation: MedicineBoxCandidateConfirmation?
    ) -> MedicineBoxRecognitionDraft? {
        if PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(plan) {
            return nil
        }
        if let editedCandidate = confirmation?.editedCandidate {
            return editedCandidate
        }
        return plan.medicineBox
    }

    /// 将单个药品计划的候选药盒与家庭已有药盒列表进行匹配。
    static func matchCandidate(
        plan: MedicationPlanRecognitionDraft,
        confirmation: MedicineBoxCandidateConfirmation?,
        familyBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        loadFailedMessage: String?
    ) -> MedicineBoxCandidateMatch {
        guard let candidate = effectiveCandidate(for: plan, confirmation: confirmation) else {
            return .noCandidate
        }
        if let loadFailedMessage {
            return .loadFailed(candidate: candidate, message: loadFailedMessage)
        }
        guard let normalized = normalizeMedicineName(
            candidateName(for: plan, editedCandidate: confirmation?.editedCandidate)
        ) else {
            return .noExisting(candidate: candidate)
        }

        let matches = familyBoxes.filter { box in
            normalizeMedicineName(box.medicineName) == normalized
        }
        switch matches.count {
        case 0:
            return .noExisting(candidate: candidate)
        case 1:
            return .uniqueExisting(candidate: candidate, target: matches[0])
        default:
            return .multipleExisting(candidate: candidate, targets: matches)
        }
    }

    /// 根据所有匹配结果和用户确认状态，计算药盒候选确认流程的概览统计。
    static func computeOverviewStats(
        batches: [PrescriptionRecognitionDraft],
        matches: [MedicationCandidateKey: MedicineBoxCandidateMatch],
        confirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation]
    ) -> PrescriptionMedicineBoxOverviewStats {
        var candidateCount = 0
        var pendingCount = 0
        var matchedExistingCount = 0
        var createNewCount = 0

        for (prescriptionIndex, batch) in batches.enumerated() {
            for (medicationIndex, plan) in (batch.medicationPlans ?? []).enumerated() {
                let key = MedicationCandidateKey(
                    prescriptionIndex: prescriptionIndex,
                    medicationIndex: medicationIndex
                )
                guard let match = matches[key], match != .noCandidate else { continue }
                candidateCount += 1

                let confirmation = confirmations[key] ?? .default
                switch match {
                case .uniqueExisting:
                    matchedExistingCount += 1
                case .multipleExisting(_, let targets):
                    if let selectedID = confirmation.selectedExistingBoxID,
                       targets.contains(where: { $0.id == selectedID }) {
                        matchedExistingCount += 1
                    }
                case .noExisting:
                    createNewCount += 1
                case .loadFailed, .noCandidate:
                    break
                }

                if confirmation.isConfirmed == false {
                    pendingCount += 1
                } else if case .multipleExisting = match, confirmation.selectedExistingBoxID == nil {
                    pendingCount += 1
                }
            }
        }

        return PrescriptionMedicineBoxOverviewStats(
            prescriptionCount: batches.count,
            medicationCount: batches.reduce(0) { $0 + ($1.medicationPlans?.count ?? 0) },
            candidateCount: candidateCount,
            pendingCount: pendingCount,
            matchedExistingCount: matchedExistingCount,
            createNewCount: createNewCount
        )
    }
}
