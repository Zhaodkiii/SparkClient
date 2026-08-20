import SwiftUI

extension HomeDashboard.MedicalCard.Kind {
    var homeMedicalListRoute: HomeMedicalListRoute {
        switch self {
        case .medicalCases:
            return .medicalCases
        case .healthExamReports:
            return .healthExamReports
        case .medicalReports:
            return .examinationReports
        case .medication:
            return .medication
        case .medicationPlans:
            return .medicationPlans
        case .familyMedicineCabinet:
            return .medication
        }
    }
}

enum HomeMedicalRouteSupport {
    @MainActor
    static func medicalListView(
        route: HomeMedicalListRoute,
        medicationFocus: MedicationExecutionInitialFocus?,
        homeViewModel: HomeViewModel,
        dependencies: HomeFeatureDependencies,
        session: UserSession,
        onDismiss: (() -> Void)? = nil
    ) -> HomeMedicalListView {
        HomeMedicalListView(
            route: route,
            completeData: homeViewModel.dashboard?.medical.completeData,
            dependencies: dependencies,
            initialFocus: medicationFocus,
            onDismiss: onDismiss,
            onMedicalCasesUpdated: { cases in
                homeViewModel.updateMedicalCompleteData { $0.medicalCases = cases }
            },
            onHealthExamReportsUpdated: { reports in
                homeViewModel.updateMedicalCompleteData { $0.healthExamReports = reports }
            },
            onExaminationReportsUpdated: { reports in
                homeViewModel.updateMedicalCompleteData { $0.examinationReports = reports }
            },
            onMedicationPlansUpdated: { plans in
                homeViewModel.updateMedicalCompleteData { $0.medicationPlans = plans }
                triggerMedicationReminderRebuild(
                    reminderEnabled: plans.contains(where: \.reminderEnabled),
                    homeViewModel: homeViewModel,
                    dependencies: dependencies,
                    session: session
                )
            },
            onPrescriptionsUpdated: { prescriptions in
                homeViewModel.updateMedicalCompleteData { $0.prescriptions = prescriptions }
            },
            onMedicineBoxesUpdated: { boxes in
                homeViewModel.updateMedicalCompleteData { $0.medicineBoxes = boxes }
            },
            selectedMemberID: homeViewModel.selectedMemberID,
            onMemberIDSelected: { memberID in
                Task { await homeViewModel.switchMemberAndLoad(memberID) }
            }
        )
    }

    @MainActor
    static func familyMedicineCabinetView(
        memberID: Int,
        homeViewModel: HomeViewModel,
        dependencies: HomeFeatureDependencies
    ) -> some View {
        FamilyMedicineCabinetPage(
            entryMemberID: memberID,
            mode: .family,
            memberCompleteData: homeViewModel.dashboard?.medical.completeData,
            onMemberCompleteDataChanged: { updated in
                homeViewModel.updateMedicalCompleteData { completeData in
                    completeData.familyMedicineBoxes = updated.familyMedicineBoxes
                }
            },
            dependencies: dependencies
        )
    }

    @MainActor
    static func triggerMedicationReminderRebuild(
        reminderEnabled: Bool,
        homeViewModel: HomeViewModel,
        dependencies: HomeFeatureDependencies,
        session: UserSession
    ) {
        let members = homeViewModel.dashboard?.members ?? dependencies.memberContextStore.context.members
        let coordinator = dependencies.medicationReminderSyncCoordinator
        guard reminderEnabled else {
            coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
            return
        }
        coordinator.activate(accountID: session.accountID)
        coordinator.rebuildAfterPlanChanged(accountID: session.accountID, members: members)
    }
}
