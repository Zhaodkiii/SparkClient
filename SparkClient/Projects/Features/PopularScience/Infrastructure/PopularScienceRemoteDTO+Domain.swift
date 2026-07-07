import Foundation

extension PopularSciencePageDTO where T == PopularScienceArticleSummaryDTO {
    func toDomain() -> PopularSciencePage<PopularScienceArticleSummary> {
        PopularSciencePage(
            items: items.map { $0.toDomain() },
            page: pagination.page,
            pageSize: pagination.pageSize,
            total: pagination.total,
            hasNext: pagination.page < pagination.totalPages
        )
    }
}

extension PopularScienceArticleSummaryDTO {
    func toDomain() -> PopularScienceArticleSummary {
        PopularScienceArticleSummary(
            id: id,
            title: title,
            slug: slug,
            locale: locale,
            summary: summary,
            coverImageURL: coverImage.flatMap(URL.init(string:)),
            category: category?.toDomain(),
            tags: (tags ?? []).map { $0.toDomain() },
            isTop: isTop ?? false,
            isRecommended: isRecommended ?? false,
            viewCount: viewCount ?? 0,
            estimatedReadingMinutes: estimatedReadingMinutes,
            publishedAt: publishedAt
        )
    }
}

extension PopularScienceArticleDetailDTO {
    func toDomain() -> PopularScienceArticleDetail {
        let mergedReferences = references?.items ?? referencesJson?.items ?? []
        let resolvedShareURL = shareUrl ?? shareLinks?.shareUrl
        return PopularScienceArticleDetail(
            id: id,
            title: title,
            slug: slug,
            locale: locale,
            translationGroupID: translationGroupId,
            summary: summary,
            coverImageURL: coverImage.flatMap(URL.init(string:)),
            content: content,
            contentFormat: contentFormat ?? "markdown",
            category: category?.toDomain(),
            tags: (tags ?? []).map { $0.toDomain() },
            sourceURL: sourceUrl.flatMap(URL.init(string:)),
            references: mergedReferences.map { $0.toDomain() },
            shareURL: resolvedShareURL.flatMap(URL.init(string:)),
            estimatedReadingMinutes: estimatedReadingMinutes,
            publishedAt: publishedAt,
            updatedAt: updatedAt
        )
    }
}

extension PopularScienceCategoryDTO {
    func toDomain() -> PopularScienceCategory {
        PopularScienceCategory(id: id, name: name, slug: slug)
    }
}

extension PopularScienceTagDTO {
    func toDomain() -> PopularScienceTag {
        PopularScienceTag(id: id, name: name, slug: slug)
    }
}

extension PopularScienceReferenceDTO {
    func toDomain() -> PopularScienceReference {
        PopularScienceReference(
            title: title,
            url: url.flatMap(URL.init(string:)),
            source: source,
            publishedAt: publishedAt
        )
    }
}

