import Foundation

struct MedicalArchiveMutationService: Sendable {
    let workflowAPI: SparkMedicalWorkflowAPI

    private static let archivableKinds: Set<SparkMedicalResourceKind> = [
        .cases, .healthExamReports, .examinationReports, .medicineBoxes, .prescriptions, .medicationPlans
    ]

    func setArchived<T: Decodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        archived: Bool
    ) async throws -> T {
        guard Self.archivableKinds.contains(kind) else {
            throw NSError(
                domain: "MedicalArchiveMutationService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Resource kind is not archivable"]
            )
        }
        return try await workflowAPI.setArchived(type, kind: kind, id: id, archived: archived)
    }
}
