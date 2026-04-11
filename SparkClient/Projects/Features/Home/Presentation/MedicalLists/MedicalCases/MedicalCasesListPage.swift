import SwiftUI

/// 病例记录列表页。
struct MedicalCasesListPage: View {
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?

    var body: some View {
        List {
            let rows = completeData?.medicalCases ?? []
            if rows.isEmpty {
                MedicalListEmptyRow()
            } else {
                ForEach(rows, id: \.id) { item in
                    MedicalRecordCard(item: item)
                        .medicalListCardRowStyle()
                }
            }
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medical_cases.title"))
    }
}
