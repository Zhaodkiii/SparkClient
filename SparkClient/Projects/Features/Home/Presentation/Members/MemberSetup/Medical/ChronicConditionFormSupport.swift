import Foundation

struct ChronicDiseaseCategoryGroup: Identifiable, Equatable {
    let titleItem: SparkBilingualItem
    let systemImage: String
    let diseaseItems: [SparkBilingualItem]

    var id: String { titleItem.cn }
    var title: String { MedicalFormBilingualCatalog.display(titleItem) }
    var diseases: [String] { diseaseItems.map(\.cn) }
}

enum ChronicConditionFormSupport {
    static var introText: String { L10n.text("member.setup.medical.chronic.intro_form") }

    static var controlStatusOptions: [String] {
        MedicalFormBilingualCatalog.chronicControlStatusOptions.map(\.cn)
    }

    static var diseaseCategories: [ChronicDiseaseCategoryGroup] {
        MedicalFormBilingualCatalog.chronicCategories.map {
            ChronicDiseaseCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, diseaseItems: $0.items)
        }
    }

    static func displayDisease(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.allChronicDiseaseItems)
    }

    static func displayControlStatus(_ stored: String) -> String {
        MedicalFormBilingualCatalog.displayStored(stored, in: MedicalFormBilingualCatalog.chronicControlStatusOptions)
    }

    static func filteredCategories(matching searchText: String) -> [ChronicDiseaseCategoryGroup] {
        MedicalFormBilingualCatalog.filteredGroups(MedicalFormBilingualCatalog.chronicCategories, matching: searchText)
            .map { ChronicDiseaseCategoryGroup(titleItem: $0.title, systemImage: $0.systemImage, diseaseItems: $0.items) }
    }

    static func summaryLine(name: String, detail: MedicalGuideChronicConditionDetail?) -> String {
        var pieces = [displayDisease(name)]
        if let detail {
            if detail.diagnosedYear.isEmpty == false {
                pieces.append(L10n.format("member.setup.medical.chronic.diagnosed_year", detail.diagnosedYear))
            }
            if detail.controlStatus.isEmpty == false {
                pieces.append(displayControlStatus(detail.controlStatus))
            }
            if detail.notes.isEmpty == false {
                pieces.append(detail.notes)
            }
        }
        return pieces.joined(separator: " · ")
    }
}
