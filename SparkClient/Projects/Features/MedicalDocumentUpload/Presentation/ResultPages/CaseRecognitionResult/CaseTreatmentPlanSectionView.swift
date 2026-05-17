import SwiftUI

struct CaseTreatmentPlanSectionView: View {
    let batches: [PrescriptionRecognitionDraft]
    let followUps: [FollowUpRecognitionDraft]
    let attachmentsForIDs: ([UUID]) -> [MedicalDocumentLocalAttachmentItem]
    let onEditBatch: (PrescriptionRecognitionDraft) -> Void
    let onEditMedicationItem: (Int, Int, MedicationPlanRecognitionDraft) -> Void
    let onEditFollowUp: (FollowUpRecognitionDraft) -> Void

    var body: some View {
        PrescriptionBatchListSectionView(
            batches: batches,
            followUps: followUps,
            title: "治疗方案",
            subtitle: "处方批次",
            badgeText: "\(batches.count)组",
            actionTitle: nil,
            attachmentsForIDs: attachmentsForIDs,
            onEditBatch: { _, batch in
                onEditBatch(batch)
            },
            onEditMedication: { batchIndex, itemIndex, item in
                onEditMedicationItem(batchIndex, itemIndex, item)
            },
            onEditFollowUp: { item in
                onEditFollowUp(item)
            }
        )
    }
}
