import Foundation

enum RegistrationCatalogServiceError: LocalizedError, Sendable {
    case hospitalNotSelected
    case hospitalUnavailable
    case departmentRequired
    case departmentNotFound
    case doctorNotFound
    case catalogUnavailable

    var code: String {
        switch self {
        case .hospitalNotSelected: return "REGISTRATION_HOSPITAL_NOT_SELECTED"
        case .hospitalUnavailable: return "REGISTRATION_HOSPITAL_UNAVAILABLE"
        case .departmentRequired: return "REGISTRATION_DEPARTMENT_REQUIRED"
        case .departmentNotFound: return "REGISTRATION_DEPARTMENT_NOT_FOUND"
        case .doctorNotFound: return "REGISTRATION_DOCTOR_NOT_FOUND"
        case .catalogUnavailable: return "REGISTRATION_CATALOG_UNAVAILABLE"
        }
    }

    var errorDescription: String? {
        switch self {
        case .hospitalNotSelected: return "请先选择医院后再查询挂号目录。"
        case .hospitalUnavailable: return "当前选择的医院暂不可用。"
        case .departmentRequired: return "查询医生前需要先选择科室。"
        case .departmentNotFound: return "当前医院没有找到这个科室，请重新查询目录。"
        case .doctorNotFound: return "当前医院没有找到这个医生，请重新查询目录。"
        case .catalogUnavailable: return "暂时无法获取当前医院的挂号目录，请稍后重试。"
        }
    }
}

struct RegistrationCatalogHospital: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
}

struct RegistrationCatalogDepartment: Codable, Equatable, Sendable {
    let id: UUID
    let code: String?
    let name: String
    let shortName: String?
    let description: String?
}

struct RegistrationCatalogDoctor: Codable, Equatable, Sendable {
    let agentID: UUID
    let doctorID: UUID
    let name: String
    let title: String
    let specialties: [String]
    let avatarURL: String?
}

struct RegistrationCatalogResult: Codable, Equatable, Sendable {
    let scope: String
    let hospital: RegistrationCatalogHospital
    let department: RegistrationCatalogDepartment?
    let departments: [RegistrationCatalogDepartment]
    let doctors: [RegistrationCatalogDoctor]
}

struct RegistrationValidatedRecommendation: Sendable {
    let hospital: RegistrationCatalogHospital
    let department: RegistrationCatalogDepartment
    let doctor: RegistrationCatalogDoctor?
}

protocol RegistrationCatalogServing: Sendable {
    func query(scope: String, departmentID: UUID?, keyword: String?, limit: Int) async throws -> RegistrationCatalogResult
    func validate(departmentID: UUID, agentID: UUID?) async throws -> RegistrationValidatedRecommendation
}

/// ToolHub 使用的医院目录适配层。医院、科室和医生均复用现有患者端目录及缓存。
final class RegistrationCatalogService: RegistrationCatalogServing, @unchecked Sendable {
    private let remoteAPI: HospitalCareRemoteAPI
    private let directory: LoadHospitalAgentDirectoryUseCase
    private let selectionStore: HospitalSelectionStore
    private let defaultAccountID: Int64
    private let sessionSnapshotStore: SessionSnapshotStore

    init(
        remoteAPI: HospitalCareRemoteAPI,
        catalogCache: HospitalCatalogMemoryCache,
        selectionStore: HospitalSelectionStore = .shared,
        accountID: Int64 = 0,
        sessionSnapshotStore: SessionSnapshotStore = SessionSnapshotStore()
    ) {
        self.remoteAPI = remoteAPI
        self.directory = LoadHospitalAgentDirectoryUseCase(
            remoteAPI: remoteAPI,
            catalogCache: catalogCache
        )
        self.selectionStore = selectionStore
        self.defaultAccountID = accountID
        self.sessionSnapshotStore = sessionSnapshotStore
    }

    func query(scope: String, departmentID: UUID?, keyword: String?, limit: Int) async throws -> RegistrationCatalogResult {
        let hospital = try await currentHospital()
        let accountID = await currentAccountID()
        let safeLimit = min(max(limit, 1), 50)
        switch scope {
        case "departments":
            let rows = try await directory.loadDepartments(accountID: accountID, hospitalID: hospital.id)
            let normalizedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let filtered = normalizedKeyword.isEmpty
                ? rows
                : rows.filter { $0.name.localizedCaseInsensitiveContains(normalizedKeyword) }
            return RegistrationCatalogResult(
                scope: scope,
                hospital: hospital,
                department: nil,
                departments: Array(filtered.prefix(safeLimit)).map {
                    RegistrationCatalogDepartment(id: $0.id, code: nil, name: $0.name, shortName: nil, description: nil)
                },
                doctors: []
            )
        case "doctors":
            guard let departmentID else { throw RegistrationCatalogServiceError.departmentRequired }
            let department = try await requireDepartment(id: departmentID, hospital: hospital)
            let cards = try await directory.loadAgents(
                accountID: accountID,
                hospitalID: hospital.id,
                departmentID: department.id,
                keyword: keyword ?? "",
                memberID: nil
            )
            let doctors = cards.prefix(safeLimit).map {
                RegistrationCatalogDoctor(
                    agentID: $0.id,
                    doctorID: $0.doctorID,
                    name: $0.doctorDisplayName,
                    title: $0.doctorTitle,
                    specialties: $0.specialties,
                    avatarURL: $0.doctorAvatarURL.isEmpty ? nil : $0.doctorAvatarURL
                )
            }
            return RegistrationCatalogResult(
                scope: scope,
                hospital: hospital,
                department: department,
                departments: [],
                doctors: Array(doctors)
            )
        default:
            throw RegistrationCatalogServiceError.catalogUnavailable
        }
    }

    func validate(departmentID: UUID, agentID: UUID?) async throws -> RegistrationValidatedRecommendation {
        let hospital = try await currentHospital()
        let accountID = await currentAccountID()
        let department = try await requireDepartment(id: departmentID, hospital: hospital)
        guard let agentID else {
            return RegistrationValidatedRecommendation(hospital: hospital, department: department, doctor: nil)
        }
        let cards = try await directory.loadAgents(
            accountID: accountID,
            hospitalID: hospital.id,
            departmentID: department.id,
            keyword: "",
            memberID: nil
        )
        guard let card = cards.first(where: { $0.id == agentID }) else {
            throw RegistrationCatalogServiceError.doctorNotFound
        }
        let doctor = RegistrationCatalogDoctor(
            agentID: card.id,
            doctorID: card.doctorID,
            name: card.doctorDisplayName,
            title: card.doctorTitle,
            specialties: card.specialties,
            avatarURL: card.doctorAvatarURL.isEmpty ? nil : card.doctorAvatarURL
        )
        return RegistrationValidatedRecommendation(hospital: hospital, department: department, doctor: doctor)
    }

    private func currentHospital() async throws -> RegistrationCatalogHospital {
        let accountID = await currentAccountID()
        guard let hospitalID = await selectionStore.selectedHospitalID(accountID: accountID) else {
            throw RegistrationCatalogServiceError.hospitalNotSelected
        }
        do {
            let hospitals = try await remoteAPI.listHospitals(page: 1, pageSize: 100)
            guard let hospital = hospitals.first(where: { $0.id == hospitalID && $0.status == "active" }) else {
                throw RegistrationCatalogServiceError.hospitalUnavailable
            }
            return RegistrationCatalogHospital(id: hospital.id, name: hospital.name)
        } catch let error as RegistrationCatalogServiceError {
            throw error
        } catch {
            throw RegistrationCatalogServiceError.catalogUnavailable
        }
    }

    private func currentAccountID() async -> Int64 {
        await sessionSnapshotStore.load()?.accountID ?? defaultAccountID
    }

    private func requireDepartment(
        id: UUID,
        hospital: RegistrationCatalogHospital
    ) async throws -> RegistrationCatalogDepartment {
        do {
            let departments = try await directory.loadDepartments(accountID: await currentAccountID(), hospitalID: hospital.id)
            guard let department = departments.first(where: { $0.id == id }) else {
                throw RegistrationCatalogServiceError.departmentNotFound
            }
            return RegistrationCatalogDepartment(id: department.id, code: nil, name: department.name, shortName: nil, description: nil)
        } catch let error as RegistrationCatalogServiceError {
            throw error
        } catch {
            throw RegistrationCatalogServiceError.catalogUnavailable
        }
    }
}
