import SwiftUI

struct ChatStructuredHealthCardPreviewContext: Hashable, Identifiable, Sendable {
    let threadID: UUID
    let messageClientID: UUID
    let blockID: UUID
    let item: ChatStructuredHealthCardItem

    var id: String {
        "\(threadID.uuidString)-\(messageClientID.uuidString)-\(blockID.uuidString)-\(item.id.uuidString)"
    }

    static func == (lhs: ChatStructuredHealthCardPreviewContext, rhs: ChatStructuredHealthCardPreviewContext) -> Bool {
        lhs.threadID == rhs.threadID &&
        lhs.messageClientID == rhs.messageClientID &&
        lhs.blockID == rhs.blockID &&
        lhs.item.id == rhs.item.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(threadID)
        hasher.combine(messageClientID)
        hasher.combine(blockID)
        hasher.combine(item.id)
    }
}

enum ChatStructuredHealthCardPreviewAdapter {
    static func supportsPreview(_ item: ChatStructuredHealthCardItem) -> Bool {
        switch item {
        case .medicationPlan, .medicineBox, .prescription:
            return true
        case .examReport:
            return decode(MedicalReportRecognitionDraft.self, from: item.draftJson) != nil
        case .medicalCase:
            return false
        }
    }

    static func medicationPlanDraft(from item: ChatStructuredHealthCardItem) -> MedicationPlanRecognitionDraft? {
        guard case .medicationPlan = item else { return nil }
        return decode(MedicationPlanRecognitionDraft.self, from: item.draftJson)
    }

    static func medicineBoxDraft(from item: ChatStructuredHealthCardItem) -> MedicineBoxRecognitionDraft? {
        guard case .medicineBox = item else { return nil }
        return decode(MedicineBoxRecognitionDraft.self, from: item.draftJson)
    }

    static func prescriptionDraft(from item: ChatStructuredHealthCardItem) -> PrescriptionRecognitionDraft? {
        guard case .prescription = item else { return nil }
        if let drafts = decode([PrescriptionRecognitionDraft].self, from: item.draftJson) {
            return drafts.first
        }
        return decode(PrescriptionRecognitionDraft.self, from: item.draftJson)
    }

    static func medicalReportDraft(from item: ChatStructuredHealthCardItem) -> MedicalReportRecognitionDraft? {
        guard case .examReport = item else { return nil }
        return decode(MedicalReportRecognitionDraft.self, from: item.draftJson)
    }

    static func updatedItem(from item: ChatStructuredHealthCardItem, draft: MedicationPlanRecognitionDraft) -> ChatStructuredHealthCardItem? {
        guard case .medicationPlan(let card) = item,
              let draftJson = encode(draft) else { return nil }
        let name = medicationDisplayName(for: draft)
        let spec = joinedNonEmpty([draft.strength, draft.dosageForm], separator: " ")
        let dosage = joinedNonEmpty([draft.dosePerTime, draft.frequencyText], separator: " · ")
        return .medicationPlan(MedicationChatCardPayload(
            id: card.id,
            draftJson: draftJson,
            isSaved: card.isSaved,
            memberId: card.memberId,
            ossFileId: card.ossFileId,
            displayName: name ?? L10n.text("common.medication"),
            specification: spec,
            dosageLine: dosage
        ))
    }

    static func updatedItem(from item: ChatStructuredHealthCardItem, draft: MedicineBoxRecognitionDraft) -> ChatStructuredHealthCardItem? {
        guard case .medicineBox(let card) = item,
              let draftJson = encode(draft) else { return nil }
        let spec = joinedNonEmpty([draft.strength, draft.dosageForm, draft.medicineType], separator: " · ")
        return .medicineBox(MedicineBoxChatCardPayload(
            id: card.id,
            draftJson: draftJson,
            isSaved: card.isSaved,
            memberId: card.memberId,
            ossFileId: card.ossFileId,
            displayName: medicineBoxDisplayName(for: draft) ?? L10n.text("medical_record.medicine_box.title"),
            specification: spec
        ))
    }

    static func updatedItem(from item: ChatStructuredHealthCardItem, draft: PrescriptionRecognitionDraft) -> ChatStructuredHealthCardItem? {
        guard case .prescription(let card) = item,
              let draftJson = encode(draft) else { return nil }
        return .prescription(PrescriptionChatCardPayload(
            id: card.id,
            draftJson: draftJson,
            isSaved: card.isSaved,
            memberId: card.memberId,
            ossFileId: card.ossFileId,
            title: trimmed(draft.institutionName) ?? L10n.text("common.prescription"),
            subtitle: trimmed(draft.diagnosis)
        ))
    }

    static func updatedItem(from item: ChatStructuredHealthCardItem, draft: MedicalReportRecognitionDraft) -> ChatStructuredHealthCardItem? {
        guard case .examReport(let card) = item,
              let draftJson = encode(draft) else { return nil }
        return .examReport(ExamReportChatCardPayload(
            id: card.id,
            draftJson: draftJson,
            isSaved: card.isSaved,
            memberId: card.memberId,
            ossFileId: card.ossFileId,
            title: trimmed(draft.title) ?? L10n.text("chat.medical_card.exam.title"),
            hospital: trimmed(draft.hospital),
            dateText: trimmed(draft.date)
        ))
    }

    static func temporaryID(for id: UUID, base: Int) -> Int {
        let compact = id.uuidString.replacingOccurrences(of: "-", with: "")
        let prefix = String(compact.prefix(8))
        let raw = Int(prefix, radix: 16) ?? abs(id.uuidString.hashValue)
        return -base - abs(raw % 90_000)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder.default.decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder.default.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func trimmed(_ text: String?) -> String? {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func joinedNonEmpty(_ values: [String?], separator: String) -> String? {
        let text = values.compactMap(trimmed).joined(separator: separator)
        return text.isEmpty ? nil : text
    }

    private static func medicationDisplayName(for draft: MedicationPlanRecognitionDraft) -> String? {
        [draft.medicineName, draft.medicineBox?.medicineName, draft.brandName].compactMap(trimmed).first
    }

    private static func medicineBoxDisplayName(for draft: MedicineBoxRecognitionDraft) -> String? {
        [draft.medicineName, draft.brandName].compactMap(trimmed).first
    }
}

struct ChatStructuredHealthCardPreviewDestination: View {
    let context: ChatStructuredHealthCardPreviewContext
    @ObservedObject var memberContextStore: MemberContextStore
    let medicalQueryAPI: SparkMedicalQueryAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let onDraftUpdated: (ChatStructuredHealthCardItem) -> Void

    private var workflowAPI: SparkMedicalWorkflowAPI {
        medicalQueryAPI.medicalWorkflowAPI
    }

    private var memberID: Int? {
        context.item.memberId ?? memberContextStore.context.selectedMemberID
    }

    var body: some View {
        if let memberID {
            destination(memberID: memberID)
        } else {
            unsupportedView(message: L10n.text("chat.medical_card.error.no_member"))
        }
    }

    @ViewBuilder
    private func destination(memberID: Int) -> some View {
        switch context.item {
        case .medicationPlan:
            medicationPlanDestination(memberID: memberID)
        case .medicineBox:
            medicineBoxDestination(memberID: memberID)
        case .prescription:
            prescriptionDestination(memberID: memberID)
        case .examReport:
            examinationReportDestination(memberID: memberID)
        case .medicalCase:
            unsupportedView(message: L10n.text("chat.medical_card.preview.unsupported", fallback: "该卡片暂不支持详情预览"))
        }
    }

    @ViewBuilder
    private func medicationPlanDestination(memberID: Int) -> some View {
        if let draft = ChatStructuredHealthCardPreviewAdapter.medicationPlanDraft(from: context.item) {
            let planID = ChatStructuredHealthCardPreviewAdapter.temporaryID(for: context.item.id, base: 41_000)
            let boxID = PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(draft)
                ? nil
                : ChatStructuredHealthCardPreviewAdapter.temporaryID(for: context.item.id, base: 31_000)
            let plan = draft.remoteMedicationPlan(memberID: memberID, id: planID, medicineBoxID: boxID)
            let boxes = boxID.map { [draft.remoteMedicineBox(memberID: memberID, id: $0)] } ?? []
            MedicationPlanDetailPage(
                mode: .localDraft,
                plan: plan,
                medicineBoxes: boxes,
                memberID: memberID,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                sourcePlanDraft: draft,
                onSaved: { _ in },
                onDeleted: { _ in },
                onMedicineBoxSaved: { _ in },
                onLocalDraftSaved: { updated in
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                },
                onLocalDraftMedicineBoxSaved: { updatedBox in
                    let updatedDraft = draft.updatingMedicineBoxCandidate(updatedBox)
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updatedDraft) {
                        onDraftUpdated(item)
                    }
                },
                onLocalDraftMedicineBoxDeleted: {
                    let updatedDraft = PrescriptionRecognitionDraftMapper.medicationPlanDraftClearedMedicineBox(from: draft)
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updatedDraft) {
                        onDraftUpdated(item)
                    }
                }
            )
        } else {
            unsupportedView(message: L10n.text("chat.medical_card.error.decode"))
        }
    }

    @ViewBuilder
    private func medicineBoxDestination(memberID: Int) -> some View {
        if let draft = ChatStructuredHealthCardPreviewAdapter.medicineBoxDraft(from: context.item) {
            let boxID = ChatStructuredHealthCardPreviewAdapter.temporaryID(for: context.item.id, base: 32_000)
            let box = draft.remoteMedicineBox(memberID: memberID, id: boxID)
            MedicineBoxDetailPage(
                mode: .localDraft,
                box: box,
                entryMemberID: memberID,
                memberOptions: memberContextStore.context.members,
                typeOptions: MedicineBoxTypeCatalog.options(in: [box]),
                specOptionBoxes: [box],
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                sourceBoxDraft: draft,
                onSaved: { _ in },
                onDeleted: { _ in },
                onLocalDraftSaved: { updated in
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                }
            )
        } else {
            unsupportedView(message: L10n.text("chat.medical_card.error.decode"))
        }
    }

    @ViewBuilder
    private func prescriptionDestination(memberID: Int) -> some View {
        if let draft = ChatStructuredHealthCardPreviewAdapter.prescriptionDraft(from: context.item) {
            let prescriptionIndex = abs(ChatStructuredHealthCardPreviewAdapter.temporaryID(for: context.item.id, base: 20_000))
            let boxes = PrescriptionRecognitionDraftMapper.remoteMedicineBoxes(
                from: draft,
                memberID: memberID,
                prescriptionIndex: prescriptionIndex
            )
            MedicationPrescriptionDetailPage(
                mode: .localDraft,
                prescription: PrescriptionRecognitionDraftMapper.remotePrescription(
                    from: draft,
                    memberID: memberID,
                    prescriptionIndex: prescriptionIndex
                ),
                plans: PrescriptionRecognitionDraftMapper.remoteMedicationPlans(
                    from: draft,
                    memberID: memberID,
                    prescriptionIndex: prescriptionIndex,
                    medicineBoxes: boxes
                ),
                medicineBoxes: boxes,
                recordsByPlanID: [:],
                memberID: memberID,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                notificationClient: notificationClient,
                prescriptionIndex: prescriptionIndex,
                sourceBatchDraft: draft,
                onPrescriptionSaved: { _ in },
                onPrescriptionDeleted: { _ in },
                onPlanSaved: { _ in },
                onPlanDeleted: { _ in },
                onLocalDraftPrescriptionUpdated: { updated in
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                },
                onLocalDraftMedicationPlanSaved: { index, updatedPlan in
                    var updated = draft
                    var plans = updated.medicationPlans ?? []
                    if plans.indices.contains(index) {
                        plans[index] = updatedPlan
                        updated.medicationPlans = plans
                    }
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                },
                onLocalDraftMedicationPlanDeleted: { index in
                    var updated = draft
                    var plans = updated.medicationPlans ?? []
                    if plans.indices.contains(index) {
                        plans.remove(at: index)
                        updated.medicationPlans = plans
                    }
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                }
            )
        } else {
            unsupportedView(message: L10n.text("chat.medical_card.error.decode"))
        }
    }

    @ViewBuilder
    private func examinationReportDestination(memberID: Int) -> some View {
        if let draft = ChatStructuredHealthCardPreviewAdapter.medicalReportDraft(from: context.item) {
            let reportID = ChatStructuredHealthCardPreviewAdapter.temporaryID(for: context.item.id, base: 11_000)
            ExaminationReportDetailPage(
                mode: .localDraft,
                report: draft.remoteExaminationReport(memberID: memberID, id: reportID),
                category: ExaminationReportCategory.from(draft.category),
                fileTransferService: fileTransferService,
                workflowAPI: workflowAPI,
                completeData: cachedCompleteData,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient,
                sourceReportDraft: draft,
                onSaved: { _ in },
                onDeleted: { _ in },
                onLocalDraftSaved: { updated in
                    if let item = ChatStructuredHealthCardPreviewAdapter.updatedItem(from: context.item, draft: updated) {
                        onDraftUpdated(item)
                    }
                }
            )
        } else {
            unsupportedView(message: L10n.text("chat.medical_card.preview.unsupported", fallback: "该卡片暂不支持详情预览"))
        }
    }

    private func unsupportedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(L10n.text("chat.medical_card.preview.title", fallback: "卡片预览"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
