import Combine
import Foundation

/// 家庭/个人药箱页面的数据与筛选状态（工单 MEDICINE-CABINET-000005 / 000006）
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
    /// 页面模式：家庭汇总或个人成员药箱
    let mode: MedicineBoxMode

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let logger: Logger

    init(
        entryMemberID: Int,
        mode: MedicineBoxMode = .family,
        initialMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = [],
        initialFamilyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]? = nil,
        medicalQueryAPI: SparkMedicalQueryAPI,
        logger: Logger
    ) {
        self.entryMemberID = entryMemberID
        self.mode = mode
        self.medicalQueryAPI = medicalQueryAPI
        self.logger = logger
        switch mode {
        case .personal:
            // 个人模式：优先用首页缓存立即展示，避免进入页面空白等待网络
            self.allBoxes = Self.sortedByUpdatedAt(initialMedicineBoxes)
        case .family:
            // 家庭模式：优先用首页 familyMedicineBoxes 缓存立即展示
            if let cached = initialFamilyMedicineBoxes, cached.isEmpty == false {
                self.allBoxes = Self.sortedByUpdatedAt(cached)
                logger.info(
                    "家庭药箱缓存命中 entryMemberID=\(entryMemberID) count=\(cached.count)",
                    module: .home
                )
            }
        }
    }

    /// 家庭模式进入页面时是否需要请求接口（缓存为 nil 或空数组）
    static func shouldLoadFamilyMedicineOnAppear(cachedBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]?) -> Bool {
        cachedBoxes?.isEmpty != false
    }

    /// 回写首页缓存用的药箱列表（与 MedicineBoxListPage.sortedBoxes 语义一致）
    var boxesForHomeCacheSync: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        Self.sortedByUpdatedAt(allBoxes)
    }

    /// 回写首页 familyMedicineBoxes 缓存用的列表
    var boxesForFamilyHomeCacheSync: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        boxesForHomeCacheSync
    }

    nonisolated static func sortedByUpdatedAt(_ boxes: [SparkMedicalSyncAPI.RemoteMedicineBox]) -> [SparkMedicalSyncAPI.RemoteMedicineBox] {
        boxes.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 是否展示人员筛选（仅家庭模式）
    var showsMemberFilter: Bool {
        mode == .family
    }

    var typeTabs: [String] {
        var tabs = [""]
        tabs.append(contentsOf: MedicineBoxTypeCatalog.options(in: allBoxes))
        return tabs
    }

    var filteredBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] {
        var items = allBoxes

        // 人员筛选仅在家庭药箱模式生效
        if mode == .family {
            switch memberFilter {
            case .all:
                break
            case .householdPublic:
                items = items.filter { $0.member == nil }
            case .member(let id):
                items = items.filter { $0.member == id }
            }
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

    /// - Returns: 是否成功从服务端拉取到最新数据
    @discardableResult
    func load() async -> Bool {
        guard Task.isCancelled == false else {
            logger.info("药箱加载跳过：Task 已取消 entryMemberID=\(entryMemberID)", module: .home)
            return false
        }
        guard isLoading == false else {
            logger.info("药箱加载跳过：已有加载任务 entryMemberID=\(entryMemberID)", module: .home)
            return false
        }

        let requestMemberID = entryMemberID
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            switch mode {
            case .family:
                if allBoxes.isEmpty {
                    logger.info(
                        "家庭药箱缓存未加载，页面内请求 entryMemberID=\(requestMemberID)",
                        module: .home
                    )
                }
                // 家庭模式：按入口成员汇总创建者名下全部成员药品与公共药品
                let boxes = try await medicalQueryAPI.listFamilyMedicineCabinet(memberID: requestMemberID)
                guard requestMemberID == entryMemberID else { return false }
                allBoxes = boxes
                logger.info("家庭药箱加载完成 entryMemberID=\(requestMemberID) count=\(allBoxes.count)", module: .home)
            case .personal:
                // 个人模式：后台刷新成员药箱；失败时保留首页缓存 allBoxes 不清空
                let boxes = try await medicalQueryAPI.listMedicineBoxes(memberID: entryMemberID)
                allBoxes = Self.sortedByUpdatedAt(boxes)
                logger.info("个人药箱加载完成 entryMemberID=\(entryMemberID) count=\(allBoxes.count)", module: .home)
            }
            return true
        } catch {
            guard Task.isCancelled == false else { return false }
            errorMessage = error.localizedDescription
            let modeLabel = mode == .family ? "家庭" : "个人"
            logger.warning("\(modeLabel)药箱加载失败 entryMemberID=\(entryMemberID) error=\(error.localizedDescription)", module: .home)
            return false
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
