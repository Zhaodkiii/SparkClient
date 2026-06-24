import Foundation

enum CatalogItemSearch {
    static func matches(_ item: String, searchText: String) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }

        let query = trimmed.lowercased()
        let queryPinyin = trimmed.toPinyinForSearch().lowercased()
        return item.localizedCaseInsensitiveContains(trimmed)
            || item.toPinyinForSearch().lowercased().contains(queryPinyin)
            || item.toPinyinForSearch().lowercased().contains(query)
            || item.toPinyinInitialsForSearch().contains(query)
    }

    static func matches(_ item: SparkBilingualItem, searchText: String) -> Bool {
        matches(item.cn, searchText: searchText) || matches(item.en, searchText: searchText)
    }
}
