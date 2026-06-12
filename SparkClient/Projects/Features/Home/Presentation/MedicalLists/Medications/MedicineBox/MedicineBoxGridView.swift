import SwiftUI

/// 药箱双列药品网格（家庭/个人模式共用）
struct MedicineBoxGridView: View {
    let boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let isLoading: Bool
    let entryMemberID: Int
    let allowsHouseholdPublic: Bool
    let memberOptions: [Member]
    let typeOptions: [String]
    let specOptionBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let onSaved: (SparkMedicalSyncAPI.RemoteMedicineBox) -> Void
    let onDeleted: (Int) -> Void

    var body: some View {
        if boxes.isEmpty {
            Text(isLoading ? L10n.text("home.medical.family_cabinet.loading") : L10n.text("home.medical.family_cabinet.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(boxes, id: \.id) { box in
                    MainNavigationLink {
                        MedicineBoxDetailPage(
                            box: box,
                            entryMemberID: entryMemberID,
                            memberOptions: memberOptions,
                            allowsHouseholdPublic: allowsHouseholdPublic,
                            typeOptions: typeOptions,
                            specOptionBoxes: specOptionBoxes,
                            workflowAPI: workflowAPI,
                            fileTransferService: fileTransferService,
                            onSaved: onSaved,
                            onDeleted: onDeleted
                        )
                    } label: {
                        MedicineBoxCardView(
                            box: box,
                            fileTransferService: fileTransferService
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
