import SwiftUI

/// 医疗资源（检查报告、用药计划、处方等）共用的「关联病历」行 + 全屏详情 / 选择病历 / 取消关联。
struct MedicalResourceMedicalCaseLinkSection<UpdatedResource: Decodable>: View {
    let memberID: Int
    let medicalCaseID: Int?
    let resourceKind: SparkMedicalResourceKind
    let resourceID: Int
    let patchField: MedicalCaseLinkPatch.Field
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let linkedTitle: String
    let linkedSubtitle: String
    let unlinkedTitle: String
    let unlinkedSubtitle: String
    let onResourceUpdated: (UpdatedResource) -> Void
    var onMedicalCaseUpdated: ((SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)?
    var onMedicalCaseDeleted: ((Int) -> Void)?

    @State private var medicalCaseRoute: MedicalCaseLinkRoute?
    @State private var isUpdatingMedicalCaseLink = false

    var body: some View {
        MedicalCaseLinkRow(
            medicalCaseID: medicalCaseID,
            linkedTitle: linkedTitle,
            linkedSubtitle: linkedSubtitle,
            unlinkedTitle: unlinkedTitle,
            unlinkedSubtitle: unlinkedSubtitle,
            detailAction: {
                if let medicalCaseID {
                    medicalCaseRoute = .detail(medicalCaseID)
                }
            },
            switchAction: {
                medicalCaseRoute = .associate
            },
            unlinkAction: {
                Task { await unlinkMedicalCase() }
            }
        ) {
            if let medicalCaseID {
                medicalCaseRoute = .detail(medicalCaseID)
            } else {
                medicalCaseRoute = .associate
            }
        }
        .fullScreenCover(item: $medicalCaseRoute) { route in
            switch route {
            case .detail(let medicalCaseID):
                CompatibleNavigationContainer {
                    LinkedMedicalCaseDetailPage(
                        medicalCaseID: medicalCaseID,
                        completeData: completeData,
                        workflowAPI: workflowAPI,
                        fileTransferService: fileTransferService,
                        memberContextStore: memberContextStore,
                        notificationClient: notificationClient,
                        onUpdated: { onMedicalCaseUpdated?($0) },
                        onDeleted: { onMedicalCaseDeleted?($0) }
                    )
                }
            case .associate:
                MedicalResourceAssociateMedicalCaseView(
                    memberID: memberID,
                    resourceKind: resourceKind,
                    resourceID: resourceID,
                    patchField: patchField,
                    workflowAPI: workflowAPI
                ) { (updated: UpdatedResource, _) in
                    onResourceUpdated(updated)
                }
            }
        }
    }

    @MainActor
    private func unlinkMedicalCase() async {
        guard isUpdatingMedicalCaseLink == false else { return }
        isUpdatingMedicalCaseLink = true
        defer { isUpdatingMedicalCaseLink = false }

        do {
            let updated = try await workflowAPI.update(
                UpdatedResource.self,
                kind: resourceKind,
                id: resourceID,
                body: MedicalCaseLinkPatch(field: patchField, medicalCaseID: nil)
            )
            onResourceUpdated(updated)
        } catch {
            notificationClient.error(
                error.localizedDescription,
                title: L10n.text("medical.case_link.unlink.failed", fallback: "取消关联失败"),
                source: "medical.case.link"
            )
        }
    }
}
