import Combine
import Foundation

@MainActor
final class HospitalSelectionViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var hospitals: [HospitalSummary] = []
    @Published private(set) var selectedHospitalID: UUID?
    @Published private(set) var submittingHospitalID: UUID?
    @Published private(set) var loadState: LoadState = .loading
    @Published var errorMessage: String?

    let accountID: Int64
    private let dependencies: HospitalCareFeatureDependencies
    private var hasLoaded = false

    init(accountID: Int64, dependencies: HospitalCareFeatureDependencies) {
        self.accountID = accountID
        self.dependencies = dependencies
        self.selectedHospitalID = dependencies.selectionStore.selectedHospitalID(accountID: accountID)
    }

    var currentHospitalDisplayName: String {
        guard let selectedHospitalID,
              let hospital = hospitals.first(where: { $0.id == selectedHospitalID }) else {
            return "未选择"
        }
        return hospital.shortName.isEmpty ? hospital.name : hospital.shortName
    }

    func load() async {
        guard hasLoaded == false else { return }
        hasLoaded = true
        await reload(forceRefresh: false)
    }

    func retry() async {
        await reload(forceRefresh: true)
    }

    func select(_ hospital: HospitalSummary) async -> Bool {
        guard submittingHospitalID == nil,
              hospital.id != selectedHospitalID else {
            return false
        }

        submittingHospitalID = hospital.id
        errorMessage = nil
        defer { submittingHospitalID = nil }
        do {
            try dependencies.selectHospital.execute(
                hospitalID: hospital.id,
                accountID: accountID,
                availableHospitals: hospitals
            )
            selectedHospitalID = hospital.id
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func reload(forceRefresh: Bool) async {
        loadState = hospitals.isEmpty ? .loading : .ready
        let resolution = await dependencies.resolveDemoHospital.execute(
            accountID: accountID,
            forceRefresh: forceRefresh
        )

        let available = (dependencies.catalogCache.hospitals(accountID: accountID) ?? [])
            .filter { $0.status.lowercased() == "active" }
        hospitals = available
        selectedHospitalID = dependencies.selectionStore.selectedHospitalID(accountID: accountID)

        switch resolution {
        case .resolved(let hospital):
            if hospitals.contains(where: { $0.id == hospital.id }) == false {
                hospitals.insert(hospital, at: 0)
            }
            selectedHospitalID = hospital.id
            loadState = .ready
        case .missing:
            loadState = .empty
        case .failed:
            loadState = hospitals.isEmpty ? .failed("医院列表加载失败，请检查网络后重试") : .ready
        }
    }
}
