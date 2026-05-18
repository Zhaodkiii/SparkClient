import SwiftUI

struct CaseTreatmentPlanSectionView: View {
    let batches: [PrescriptionRecognitionDraft]
    let followUps: [FollowUpRecognitionDraft]
    let attachmentsForIDs: ([UUID]) -> [MedicalDocumentLocalAttachmentItem]
    let onEditBatch: (PrescriptionRecognitionDraft) -> Void
    let onEditMedicationItem: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    let onEditFollowUp: (FollowUpRecognitionDraft) -> Void
    var detailNavigationContext: MedicalDocumentResultDetailNavigationContext?
    var onManageBatchAttachments: ((Int, PrescriptionRecognitionDraft) -> Void)?
    var onManageMedicationAttachments: ((Int, Int, MedicationPlanRecognitionDraft) -> Void)?
    var onManageFollowUpAttachments: ((Int, FollowUpRecognitionDraft) -> Void)?

    var body: some View {
        PrescriptionBatchListSectionView(
            batches: batches,
            followUps: followUps,
            title: "治疗方案",
            subtitle: "处方批次",
            badgeText: "\(batches.count)组",
            actionTitle: nil,
            attachmentsForIDs: attachmentsForIDs,
            detailNavigationContext: detailNavigationContext,
            onEditBatch: { _, batch in
                onEditBatch(batch)
            },
            onEditMedication: { batchIndex, itemIndex, item in
                onEditMedicationItem(batchIndex, itemIndex, item)
            },
            onEditFollowUp: { item in
                onEditFollowUp(item)
            },
            onManageBatchAttachments: onManageBatchAttachments,
            onManageMedicationAttachments: onManageMedicationAttachments,
            onManageFollowUpAttachments: onManageFollowUpAttachments
        )
    }
}
