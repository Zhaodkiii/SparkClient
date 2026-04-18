import CoreGraphics
import UIKit

/// 底部锚定与「是否在底部附近」判定（对齐 Signal `safeDistanceFromBottom` 思路）。
enum ScrollAnchorPolicy {
    /// 认为用户「贴底」的距离阈值（pt）。
    static let pinnedDistanceThreshold: CGFloat = 80

    static func distanceFromBottom(collectionView: UICollectionView) -> CGFloat {
        let layoutHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        guard layoutHeight > 0, collectionView.bounds.height > 0 else { return 0 }
        let visibleBottom = collectionView.contentOffset.y
            + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        return layoutHeight - visibleBottom
    }

    static func isPinnedToBottom(collectionView: UICollectionView) -> Bool {
        distanceFromBottom(collectionView: collectionView) <= pinnedDistanceThreshold
    }

    static func shouldFollowStream(collectionView: UICollectionView, userDragging: Bool) -> Bool {
        !userDragging && isPinnedToBottom(collectionView: collectionView)
    }
}
