import SwiftUI
import UIKit

@MainActor
final class DeepTutorMessageListViewController: UIViewController, UICollectionViewDelegate {
    private struct ScrollAnchor {
        let itemID: UUID
        let offsetFromTop: CGFloat
    }

    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private var rowModelLookup: [UUID: DeepTutorMessageRowModel] = [:]
    private var lastRenderedMessages: [DeepTutorMessage] = []
    private var lastScrollToBottomRequestGeneration: UInt64 = 0
    private var userDragging = false
    private var hasUserInteractedSinceOpen = false
    private var bottomViewportLockActive = false
    private var refreshControl: UIRefreshControl?
    private var isApplyingSnapshot = false
    private var pendingApply: (conversationID: UUID, payload: DeepTutorListApplyPayload)?
    private var lastAppliedSignature: DeepTutorListApplySignature?
    private var lastConversationID: UUID?
    weak var refreshHandler: (any DeepTutorMessageListRefreshHandling)?
    weak var renderObserver: (any DeepTutorMessageListRenderStateObserving)?
    var onLoadMore: (() -> Void)?
    var onUserInteraction: (() -> Void)?
    var rowActions: DeepTutorMessageRowActions?
    var rowMembers: [Member] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120)))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120)), subitems: [item])
            return NSCollectionLayoutSection(group: group)
        }
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
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        collectionView = cv
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        cv.refreshControl = refresh
        refreshControl = refresh
        configureDataSource()
    }

    func resetForNewThread() {
        lastRenderedMessages = []
        lastScrollToBottomRequestGeneration = 0
        userDragging = false
        hasUserInteractedSinceOpen = false
        bottomViewportLockActive = false
        isApplyingSnapshot = false
        pendingApply = nil
        lastAppliedSignature = nil
        lastConversationID = nil
        rowModelLookup = [:]
    }

    func apply(conversationID: UUID, payload: DeepTutorListApplyPayload) {
        if lastConversationID != conversationID {
            resetForNewThread()
            lastConversationID = conversationID
        }

        let signature = DeepTutorListApplySignature.make(conversationID: conversationID, payload: payload)
        if signature == lastAppliedSignature {
            DeepTutorChatLog.listSnapshotApplySkipped(conversationID: conversationID, reason: "same_signature")
            return
        }

        if isApplyingSnapshot {
            pendingApply = (conversationID, payload)
            DeepTutorChatLog.listSnapshotApplyQueued(conversationID: conversationID, reason: "reentrant_guard")
            return
        }

        performApply(conversationID: conversationID, payload: payload, signature: signature)
    }

    private func performApply(
        conversationID: UUID,
        payload: DeepTutorListApplyPayload,
        signature: DeepTutorListApplySignature
    ) {
        isApplyingSnapshot = true
        renderObserver?.messageListWillApplySnapshot(conversationID: conversationID)
        let start = Date()
        let itemCount = payload.rowModels.count + (payload.hasMoreMessages ? 1 : 0)
        DeepTutorChatLog.listSnapshotApplyStart(
            conversationID: conversationID,
            itemCount: itemCount,
            signature: signature.contentFingerprint
        )

        rowModelLookup = Dictionary(uniqueKeysWithValues: payload.rowModels.map { ($0.id, $0) })
        let messages = payload.messages
        let shouldForceScroll = payload.scrollToBottomRequestGeneration != lastScrollToBottomRequestGeneration
        lastScrollToBottomRequestGeneration = payload.scrollToBottomRequestGeneration
        bottomViewportLockActive = payload.lockBottomViewport && hasUserInteractedSinceOpen == false

        let previous = payload.forceFullListRediff ? [] : lastRenderedMessages
        let plan = DeepTutorConversationUpdateBuilder.plan(previous: previous, current: messages)
        let wasPinned = ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView)
        let topAnchor = plan.hasPrependedItems ? captureTopAnchor() : nil

        var items: [UUID] = []
        if payload.hasMoreMessages {
            items.append(DeepTutorListLayoutConstants.loadMoreRowUUID)
        }
        items.append(contentsOf: messages.map(\.clientMessageID))
        lastRenderedMessages = messages

        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        let reloadable = plan.reloadedItemIDs.filter { snapshot.indexOfItem($0) != nil }
        if reloadable.isEmpty == false {
            snapshot.reloadItems(reloadable)
        }

        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            if shouldForceScroll {
                self.scrollToBottom(force: true)
            } else if self.bottomViewportLockActive {
                self.scrollToBottom(force: true)
            } else if plan.hasPrependedItems, let topAnchor {
                self.restoreTopAnchor(topAnchor)
            } else if plan.kind == .structural, plan.hasAppendedItems, wasPinned {
                self.scrollToBottom(force: false)
            } else if reloadable.isEmpty == false,
                      ScrollAnchorPolicy.shouldFollowStream(collectionView: self.collectionView, userDragging: self.userDragging) {
                self.scrollToBottom(force: false)
            }

            self.isApplyingSnapshot = false
            self.lastAppliedSignature = signature
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            self.renderObserver?.messageListDidApplySnapshot(conversationID: conversationID, durationMs: durationMs)

            if let pending = self.pendingApply {
                self.pendingApply = nil
                DeepTutorChatLog.listSnapshotApplyDone(
                    conversationID: conversationID,
                    hasPending: true,
                    durationMs: durationMs
                )
                let pendingSignature = DeepTutorListApplySignature.make(
                    conversationID: pending.conversationID,
                    payload: pending.payload
                )
                if pendingSignature != self.lastAppliedSignature {
                    self.performApply(
                        conversationID: pending.conversationID,
                        payload: pending.payload,
                        signature: pendingSignature
                    )
                }
            } else {
                DeepTutorChatLog.listSnapshotApplyDone(
                    conversationID: conversationID,
                    hasPending: false,
                    durationMs: durationMs
                )
            }
        }
    }

    @objc private func handleRefresh() {
        guard let refreshHandler else {
            refreshControl?.endRefreshing()
            return
        }
        Task {
            await refreshHandler.refreshMessageList()
            await MainActor.run { self.refreshControl?.endRefreshing() }
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [weak self] cell, _, itemID in
            guard let self else { return }
            if itemID == DeepTutorListLayoutConstants.loadMoreRowUUID {
                cell.contentConfiguration = UIHostingConfiguration {
                    Button("Load more") { self.onLoadMore?() }
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            } else if let rowModel = self.rowModelLookup[itemID], let actions = self.rowActions {
                DeepTutorChatLog.messageRowConfigureCell(
                    conversationID: rowModel.conversationID,
                    messageID: rowModel.message.id,
                    signature: rowModel.renderSignature
                )
                cell.contentConfiguration = UIHostingConfiguration {
                    DeepTutorMessageRowView(model: rowModel, actions: actions, members: self.rowMembers)
                }
            } else {
                cell.contentConfiguration = UIHostingConfiguration {
                    EmptyView()
                }
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, itemID in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemID)
        }
    }

    private func scrollToBottom(force: Bool) {
        guard let collectionView else { return }
        if !force, !ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView) { return }
        let items = dataSource.snapshot().itemIdentifiers
        guard let last = items.last else { return }
        if let indexPath = dataSource.indexPath(for: last) {
            collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
        }
    }

    private func captureTopAnchor() -> ScrollAnchor? {
        for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
            guard let itemID = dataSource.itemIdentifier(for: indexPath),
                  itemID != DeepTutorListLayoutConstants.loadMoreRowUUID,
                  let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
            return ScrollAnchor(itemID: itemID, offsetFromTop: attributes.frame.minY - collectionView.contentOffset.y)
        }
        return nil
    }

    private func restoreTopAnchor(_ anchor: ScrollAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.itemID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let targetY = attributes.frame.minY - anchor.offsetFromTop
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userDragging = true
        hasUserInteractedSinceOpen = true
        onUserInteraction?()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { userDragging = false }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userDragging = false
    }
}

struct DeepTutorMessageListRepresentable: UIViewControllerRepresentable {
    let conversationID: UUID
    @ObservedObject var viewModel: DeepTutorChatViewModel
    @ObservedObject var refreshCoordinator: DeepTutorRefreshCoordinator

    func makeUIViewController(context: Context) -> DeepTutorMessageListViewController {
        let controller = DeepTutorMessageListViewController()
        wire(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: DeepTutorMessageListViewController, context: Context) {
        uiViewController.renderObserver = viewModel
        let payload = DeepTutorListApplyPayload(
            rowModels: viewModel.makeMessageRowModels(),
            hasMoreMessages: viewModel.state.hasMoreMessages,
            isLoadingMoreMessages: false,
            lockBottomViewport: viewModel.state.lockBottomViewport,
            scrollToBottomRequestGeneration: viewModel.state.scrollToBottomRequestGeneration,
            forceFullListRediff: context.coordinator.appliedLayoutNonce != refreshCoordinator.layoutNonce
        )
        context.coordinator.appliedLayoutNonce = refreshCoordinator.layoutNonce
        uiViewController.rowMembers = viewModel.availableMembers
        uiViewController.apply(conversationID: conversationID, payload: payload)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appliedLayoutNonce: UInt64?
    }

    private func wire(_ controller: DeepTutorMessageListViewController) {
        controller.refreshHandler = refreshCoordinator
        controller.renderObserver = viewModel
        controller.onLoadMore = {
            Task { await viewModel.loadMoreHistory(for: conversationID) }
        }
        controller.onUserInteraction = {
            viewModel.handleUserScrollInteraction()
        }
        controller.rowMembers = viewModel.availableMembers
        controller.rowActions = DeepTutorMessageRowActions(
            onCopy: { messageID in
                viewModel.handleRowCopy(messageID: messageID)
            },
            onEdit: { messageID, newText in
                Task { await viewModel.handleRowEdit(messageID: messageID, newText: newText) }
            },
            onRetry: { messageID in
                Task { await viewModel.handleRowRetry(messageID: messageID) }
            },
            onSelectBranch: { parentMessageID, branchIndex in
                viewModel.handleRowSelectBranch(parentMessageID: parentMessageID, branchIndex: branchIndex)
            },
            onSubmitAskUser: { messageID, toolCallID, answers in
                Task {
                    await viewModel.submitAskUser(
                        assistantMessageID: messageID,
                        toolCallID: toolCallID,
                        answers: answers
                    )
                }
            },
            onSubmitMemberSelection: { messageID, toolCallID, memberID in
                Task {
                    await viewModel.submitMemberSelection(
                        assistantMessageID: messageID,
                        toolCallID: toolCallID,
                        memberID: memberID
                    )
                }
            },
            onQuizFollowUp: { prefill in
                viewModel.startQuizFollowUp(prefill: prefill)
            },
            onQuizJudge: { question, userAnswer in
                await viewModel.judgeQuizAnswer(question: question, userAnswer: userAnswer)
            },
            onQuizInlineInputFocusChanged: { focused in
                viewModel.setQuizInlineInputFocused(focused)
            }
        )
    }
}
