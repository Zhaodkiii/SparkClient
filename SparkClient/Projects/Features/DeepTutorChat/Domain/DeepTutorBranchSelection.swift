import Foundation

/// 编辑分支选择状态，对齐 Web `selectedBranches`。
nonisolated struct DeepTutorBranchSelection: Equatable, Sendable {
    /// parent message id → selected branch index (0-based)
    var selectedIndices: [UUID: Int]

    nonisolated init(selectedIndices: [UUID: Int] = [:]) {
        self.selectedIndices = selectedIndices
    }

    func selectedIndex(for parentMessageID: UUID) -> Int {
        selectedIndices[parentMessageID, default: 0]
    }

    func selecting(branchIndex: Int, for parentMessageID: UUID) -> DeepTutorBranchSelection {
        var copy = selectedIndices
        copy[parentMessageID] = branchIndex
        return DeepTutorBranchSelection(selectedIndices: copy)
    }
}
