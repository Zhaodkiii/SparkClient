import Combine
import Foundation

@MainActor
final class FamilyMedicineCabinetViewModel: ObservableObject {
    enum MemberFilter: Hashable {
        case all
        case householdPublic
        case member(Int)
    }

    @Published private(set) var allBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = []
    @Published var selectedTypeTab: String = ""
    @Published var memberFilter: MemberFilter = .all
    @Published var searchText: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let entryMemberID: Int

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger

    init(entryMemberID: Int, medicalQueryAPI: SparkMedicalQueryAPI, logger: Logger) {
        self.entryMemberID = entryMemberID
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
    }

    var typeTabs: [String] {
        var tabs = [""]
        tabs.append(contentsOf: MedicineBoxTypeCatalog.options(in: allBoxes))
        return tabs
    }

    var filteredBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        var items = allBoxes

        switch memberFilter {
        case .all:
            break
        case .householdPublic:
            items = items.filter { $0.member == nil }
        case .member(let id):
            items = items.filter { $0.member == id }
        }

        let typeKey = MedicineBoxTypeCatalog.storedValue(fromAny: selectedTypeTab.nilIfBlank)
        if typeKey.isEmpty == false {
            items = items.filter {
                MedicineBoxTypeCatalog.storedValue(fromAny: $0.medicineType) == typeKey
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty == false {
            items = items.filter { box in
                let haystack = [
                    box.medicineName,
                    box.brandName,
                    box.strength,
                    box.dosageForm
                ]
                .joined(separator: " ")
                .lowercased()
                return haystack.contains(query.lowercased())
            }
        }

        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            allBoxes = try await medicalQueryAPI.listFamilyMedicineCabinet(memberID: entryMemberID)
            logger.info("家庭药箱加载完成 entryMemberID=\(entryMemberID) count=\(allBoxes.count)", module: .home)
        } catch {
            errorMessage = error.localizedDescription
            logger.warning("家庭药箱加载失败 entryMemberID=\(entryMemberID) error=\(error.localizedDescription)", module: .home)
        }
    }

    func upsert(_ box: SparkMedicalSyncAPI.RemoteMedicineBox) {
        if let index = allBoxes.firstIndex(where: { $0.id == box.id }) {
            allBoxes[index] = box
        } else {
            allBoxes.insert(box, at: 0)
        }
    }

    func remove(id: Int) {
        allBoxes.removeAll { $0.id == id }
    }

    func clearError() {
        errorMessage = nil
    }

    func memberFilterOptions(members: [Member]) -> [(MemberFilter, String)] {
        var options: [(MemberFilter, String)] = [
            (.all, L10n.text("common.all")),
            (.householdPublic, L10n.text("home.medical.medicine_box.ownership.household"))
        ]
        let memberIDs = Set(allBoxes.compactMap(\.member))
        for id in memberIDs.sorted() {
            let name = members.first(where: { $0.id == id })?.name
                ?? L10n.text("home.medical.medicine_box.ownership.member_fallback")
            options.append((.member(id), name))
        }
        return options
    }
}
