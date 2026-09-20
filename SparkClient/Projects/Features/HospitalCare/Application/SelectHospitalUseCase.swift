import Foundation

@MainActor
struct SelectHospitalUseCase {
    let selectionStore: HospitalSelectionStore

    func execute(
        hospitalID: UUID,
        accountID: Int64,
        availableHospitals: [HospitalSummary]
    ) throws {
        guard availableHospitals.contains(where: { $0.id == hospitalID }) else {
            throw SelectHospitalError.hospitalUnavailable
        }
        selectionStore.select(
            hospitalID: hospitalID,
            accountID: accountID,
            source: .user
        )
    }
}

enum SelectHospitalError: LocalizedError {
    case hospitalUnavailable

    var errorDescription: String? {
        switch self {
        case .hospitalUnavailable:
            return "医院信息已更新，请刷新后重新选择"
        }
    }
}
