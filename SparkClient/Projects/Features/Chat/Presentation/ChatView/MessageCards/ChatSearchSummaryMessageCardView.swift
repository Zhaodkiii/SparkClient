import SwiftUI

struct ChatSearchSummaryMessageCardView: View {
    let payload: ChatSearchSummaryCardPayload
    @State private var isExpanded = false
    @State private var activeWebURL: IdentifiableURL?

    private var summaryTitle: String {
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let keywordCount = payload.keywords.count
        let referenceCount = payload.references.count
        return isChinese
            ? "搜索 \(keywordCount) 个关键词，引用 \(referenceCount) 篇资料作为参考"
            : "\(keywordCount) keyword(s), \(referenceCount) reference(s)"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if payload.keywords.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "搜索关键词" : "Keywords")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        SparkTagFlowLayout(spacing: 6) {
                            ForEach(payload.keywords, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                if payload.references.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "参考资料" : "References")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        ForEach(payload.references) { reference in
                            Button {
                                guard let url = URL(string: reference.url), isWebURL(url) else { return }
                                activeWebURL = IdentifiableURL(url: url)
                            } label: {
                                referenceRow(reference: reference)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                Text(summaryTitle)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .sheet(item: $activeWebURL) { item in
            SafariWebViewSheet(url: item.url)
                .ignoresSafeArea()
        }
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func referenceRow(reference: ChatSearchSummaryReference) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.caption2)
            Text(reference.title.isEmpty ? reference.url : reference.title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
