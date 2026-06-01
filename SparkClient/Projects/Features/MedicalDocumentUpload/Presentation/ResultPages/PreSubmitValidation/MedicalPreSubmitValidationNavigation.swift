import SwiftUI

@MainActor
enum MedicalPreSubmitValidationNavigation {
    private static let scrollDelayNanoseconds: UInt64 = 150_000_000

    /// 展开错误所在折叠模块（及体检分类），延迟后滚动到目标锚点。
    static func reveal(
        issue: MedicalPreSubmitValidationIssue,
        expandedSectionIDs: Binding<Set<String>>,
        expandedHealthExamCategories: Binding<Set<String>>? = nil,
        healthExamCategoryForItemIndex: ((Int) -> String?)? = nil,
        scrollProxy: ScrollViewProxy
    ) {
        if let sectionID = issue.collapseSectionID {
            expandedSectionIDs.wrappedValue.insert(sectionID)
        }
        if let index = issue.healthExamItemIndex,
           let category = healthExamCategoryForItemIndex?(index) {
            expandedHealthExamCategories?.wrappedValue.insert(category)
        }

        let targetID = issue.scrollTargetID
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: scrollDelayNanoseconds)
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    /// 预校验失败后自动定位第一条阻断错误（同一 issue 不重复滚动）。
    static func autoRevealFirstBlockingIssueIfNeeded(
        issues: [MedicalPreSubmitValidationIssue],
        lastAutoRevealedIssueID: inout UUID?,
        expandedSectionIDs: Binding<Set<String>>,
        expandedHealthExamCategories: Binding<Set<String>>? = nil,
        healthExamCategoryForItemIndex: ((Int) -> String?)? = nil,
        scrollProxy: ScrollViewProxy
    ) {
        guard let first = issues.blockingIssues.first else {
            lastAutoRevealedIssueID = nil
            return
        }
        guard lastAutoRevealedIssueID != first.id else { return }
        lastAutoRevealedIssueID = first.id
        reveal(
            issue: first,
            expandedSectionIDs: expandedSectionIDs,
            expandedHealthExamCategories: expandedHealthExamCategories,
            healthExamCategoryForItemIndex: healthExamCategoryForItemIndex,
            scrollProxy: scrollProxy
        )
    }
}
