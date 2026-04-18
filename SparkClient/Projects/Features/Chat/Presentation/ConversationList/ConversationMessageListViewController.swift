import SwiftUI
import UIKit

/// UIKit 承载的会话消息列表：`DiffableDataSource` 增量更新 + 底部锚定 + 键盘 inset。
@MainActor
final class ConversationMessageListViewController: UIViewController, UICollectionViewDelegate {
    private struct ScrollAnchor {
        let itemID: UUID
        let offsetFromTop: CGFloat
    }

    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private var messageLookup: [UUID: ChatMessage] = [:]
    private var lastStreamingGeneration: UInt64 = 0
    private var userDragging = false
    private var hasUserInteractedSinceThreadOpen = false
    private var bottomViewportLockActive = false
    private var lastLockedContentHeight: CGFloat = 0
    private var lastAppliedMessageIDs: [UUID] = []
    private var lastRenderedMessages: [ChatMessage] = []

    weak var stateStore: ChatStateStore?
    weak var detailViewModel: ChatDetailViewModel?
    weak var uiStateStore: ChatMessageUIStateStore?
    weak var speechHelper: ChatSpeechHelper?
    var taskManager: TaskManager?
    var logger: Logger?
    var actionState: ChatMessageActionState?
    var onLoadMore: (() -> Void)?
    var onRefresh: (() async -> Void)?

    private var refreshControl: UIRefreshControl?
    private var isLoadingMoreFlag: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let layout = Self.makeCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.delegate = self
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .interactive
        view.addSubview(cv)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: view.topAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        collectionView = cv

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        cv.refreshControl = refresh
        refreshControl = refresh

        configureDataSource()
    }

    func resetForNewThread() {
        lastAppliedMessageIDs = []
        lastStreamingGeneration = 0
        lastRenderedMessages = []
        userDragging = false
        hasUserInteractedSinceThreadOpen = false
        bottomViewportLockActive = false
        lastLockedContentHeight = 0
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        maintainBottomViewportLockIfNeeded()
    }

    @objc private func handleRefresh() {
        guard let onRefresh else {
            refreshControl?.endRefreshing()
            return
        }
        Task {
            await onRefresh()
            await MainActor.run {
                self.refreshControl?.endRefreshing()
            }
        }
    }

    func apply(threadID: UUID, payload: ConversationListApplyPayload) {
        guard let collectionView else { return }
        _ = threadID
        isLoadingMoreFlag = payload.isLoadingMoreMessages
        let messages = payload.messages
        let hasMoreMessages = payload.hasMoreMessages
        let streamingContentGeneration = payload.streamingContentGeneration
        bottomViewportLockActive = payload.lockBottomViewport && hasUserInteractedSinceThreadOpen == false
        let previousForPlan = payload.forceFullListRediff ? [] : lastRenderedMessages
        let updatePlan = ConversationUpdateBuilder.plan(previous: previousForPlan, current: messages)
        let wasPinnedToBottom = ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView)
        let topAnchor = updatePlan.hasPrependedItems ? captureTopAnchor() : nil

        var items: [UUID] = []
        if hasMoreMessages {
            items.append(ConversationListLayoutConstants.loadMoreRowUUID)
        }
        for m in messages {
            items.append(m.clientMessageID)
        }

        var lookup: [UUID: ChatMessage] = [:]
        for m in messages {
            lookup[m.clientMessageID] = m
        }
        messageLookup = lookup

        let newMessageOrder = messages.map(\.clientMessageID)
        lastAppliedMessageIDs = newMessageOrder
        lastRenderedMessages = messages

        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        let reloadableIDs = updatePlan.reloadedItemIDs.filter { snapshot.indexOfItem($0) != nil }
        if reloadableIDs.isEmpty == false {
            snapshot.reloadItems(reloadableIDs)
        }

        let genBump = streamingContentGeneration != lastStreamingGeneration
        lastStreamingGeneration = streamingContentGeneration

        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.collectionView.layoutIfNeeded()
            if self.bottomViewportLockActive {
                self.maintainBottomViewportLockIfNeeded(force: true)
            } else if updatePlan.hasPrependedItems, let topAnchor {
                self.restoreTopAnchor(topAnchor)
            } else if updatePlan.kind == .structural {
                if updatePlan.hasAppendedItems && wasPinnedToBottom {
                    self.scrollToBottom(animated: false, force: false)
                }
            } else if genBump {
                if ScrollAnchorPolicy.shouldFollowStream(collectionView: self.collectionView, userDragging: self.userDragging) {
                    self.scrollToBottom(animated: false, force: false)
                }
            }
        }
    }

    private func captureTopAnchor() -> ScrollAnchor? {
        let visible = collectionView.indexPathsForVisibleItems.sorted()
        for indexPath in visible {
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  itemID != ConversationListLayoutConstants.loadMoreRowUUID,
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                continue
            }
            return ScrollAnchor(
                itemID: itemID,
                offsetFromTop: attributes.frame.minY - collectionView.contentOffset.y
            )
        }
        return nil
    }

    private func restoreTopAnchor(_ anchor: ScrollAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.itemID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return
        }
        let targetY = attributes.frame.minY - anchor.offsetFromTop
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: targetY), animated: false)
    }

    private func scrollToBottom(animated: Bool, force: Bool) {
        guard let collectionView else { return }
        let n = collectionView.numberOfItems(inSection: 0)
        guard n > 0 else { return }
        if force == false && ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView) == false {
            return
        }
        let indexPath = IndexPath(item: n - 1, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }

    private func maintainBottomViewportLockIfNeeded(force: Bool = false) {
        guard bottomViewportLockActive, hasUserInteractedSinceThreadOpen == false else { return }
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        guard force || abs(contentHeight - lastLockedContentHeight) > 0.5 else { return }
        lastLockedContentHeight = contentHeight
        scrollToBottom(animated: false, force: true)
    }

    // MARK: - UICollectionViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userDragging = true
        hasUserInteractedSinceThreadOpen = true
        bottomViewportLockActive = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if decelerate == false {
            userDragging = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userDragging = false
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if bottomViewportLockActive,
           indexPath.section == 0,
           indexPath.item == collectionView.numberOfItems(inSection: 0) - 1 {
            maintainBottomViewportLockIfNeeded(force: true)
        }
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        if item == ConversationListLayoutConstants.loadMoreRowUUID {
            onLoadMore?()
        }
    }

    // MARK: - Layout & data source

    private static func makeCompositionalLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(140)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(140)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<ConversationHostingCell, UUID> { [weak self] cell, _, item in
            guard let self else { return }
            cell.configure(parent: self, content: self.hostedContent(for: item))
        }
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(
            collectionView: collectionView,
            cellProvider: { collectionView, indexPath, item in
                collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
            }
        )
    }

    @ViewBuilder
    private func hostedContent(for item: UUID) -> some View {
        if item == ConversationListLayoutConstants.loadMoreRowUUID {
            ConversationLoadMoreRow(isLoading: isLoadingMoreFlag)
        } else {
            let clientID = item
            if let msg = messageLookup[clientID],
               let stateStore,
               let detailViewModel,
               let uiStateStore,
               let speechHelper,
               let actionState,
               let taskManager,
               let logger {
                let threadID = msg.threadID
                let all = stateStore.conversationListItems(for: threadID).filter { uiStateStore.isDeleted($0.id) == false }
                ChatConversationMessageRow(
                    threadID: threadID,
                    message: msg,
                    visibleMessages: all,
                    stateStore: stateStore,
                    detailViewModel: detailViewModel,
                    uiStateStore: uiStateStore,
                    speechHelper: speechHelper,
                    actionState: actionState,
                    taskManager: taskManager,
                    logger: logger
                )
            } else {
                Color.clear.frame(height: 1)
            }
        }
    }
}

// MARK: - Load more row

private struct ConversationLoadMoreRow: View {
    let isLoading: Bool
    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView()
            } else {
                Text(L10n.text("chat.history.load_more"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Hosting cell

private final class ConversationHostingCell: UICollectionViewCell {
    private var hostingController: UIHostingController<AnyView>?

    func configure(parent: UIViewController, content: some View) {
        let wrapped = AnyView(content)
        if let hostingController {
            hostingController.rootView = wrapped
            hostingController.view.invalidateIntrinsicContentSize()
        } else {
            let hc = UIHostingController(rootView: wrapped)
            hc.view.backgroundColor = .clear
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            parent.addChild(hc)
            contentView.addSubview(hc.view)
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
            hc.didMove(toParent: parent)
            hostingController = hc
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}
