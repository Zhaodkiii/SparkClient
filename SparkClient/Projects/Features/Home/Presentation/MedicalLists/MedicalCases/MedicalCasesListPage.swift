import SwiftUI

/// 病例记录列表页。
struct MedicalCasesListPage: View {
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let onCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?

    @State private var rows: [SparkMedicalSyncAPI.RemoteMedicalCaseSummary]
    @State private var showingCreateSheet = false

    init(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        memberContextStore: MemberContextStore,
        notificationClient: any NotificationClient,
        onCasesUpdated: (([SparkMedicalSyncAPI.RemoteMedicalCaseSummary]) -> Void)?
    ) {
        self.completeData = completeData
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.memberContextStore = memberContextStore
        self.notificationClient = notificationClient
        self.onCasesUpdated = onCasesUpdated
        _rows = State(initialValue: completeData?.medicalCases ?? [])
    }

    var body: some View {
        List {
            if rows.isEmpty {
                MedicalListEmptyRow()
            } else {
                ForEach(rows, id: \.id) { item in
                    MedicalRecordCard(
                        item: item,
                        completeData: completeData,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient,
                        onUpdated: upsertCase,
                        onDeleted: removeCase
                    )
                        .medicalListCardRowStyle()
                }
            }
        }
        .listStyle(.plain)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("home.medical.list.medical_cases.title"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: completeData?.medicalCases ?? []) { newValue in
            rows = newValue
        }
        .sheet(isPresented: $showingCreateSheet) {
            CompatibleNavigationContainer {
                MedicalCaseFormView(
                    mode: .create(memberID: defaultMemberID, onSaved: upsertCase),
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    notificationClient: notificationClient
                )
            }
        }
    }

    private var defaultMemberID: Int {
        completeData?.member.id ?? memberContextStore.context.selectedMember?.id ?? 0
    }

    private func upsertCase(_ item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        if let index = rows.firstIndex(where: { $0.id == item.id }) {
            rows[index] = item
        } else {
            rows.insert(item, at: 0)
        }
        onCasesUpdated?(rows)
    }

    private func removeCase(_ id: Int) {
        rows.removeAll { $0.id == id }
        onCasesUpdated?(rows)
    }
}
