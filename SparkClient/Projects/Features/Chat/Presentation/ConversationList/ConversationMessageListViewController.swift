import SwiftUI
import UIKit

/// UIKit 承载的会话消息列表：`DiffableDataSource` 增量更新 + 底部锚定 + 键盘 inset。

///
/// UIKit 聊天会话消息列表控制器
/// 核心能力：
/// 1. Diffable DataSource 增量更新消息（高性能、无闪烁）
/// 2. 流式消息自动滚动到底部
/// 3. 键盘弹出/隐藏时自动保持视口
/// 4. 下拉刷新 + 上拉加载更多
/// 5. 滚动锚定（顶部插入消息不跳动、底部锁定）
///
@MainActor
final class ConversationMessageListViewController: UIViewController, UICollectionViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - 滚动锚点（顶部插入消息时保持位置不跳动）
    private struct ScrollAnchor {
        let itemID: UUID           // 锚定的消息 ID
        let offsetFromTop: CGFloat // 距离顶部的偏移量
    }

    // MARK: - UI 组件
    private(set) var collectionView: UICollectionView! // 消息列表（UICollectionView）
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>! // 增量数据源
    private var messageLookup: [UUID: ChatMessage] = [:] // 消息 ID → 消息模型映射

    // MARK: - 流式渲染状态
    private var lastScrollToBottomRequestGeneration: UInt64 = 0 // 发送等主动动作触发的强制贴底版本号
    private var userDragging = false // 用户是否正在手动拖拽列表
    private var hasUserInteractedSinceThreadOpen = false // 用户是否交互过（交互后不再自动滚到底部）
    
    // MARK: - 视口锁定（AI 回复时强制贴底）
    private var bottomViewportLockActive = false // 是否激活底部锁定
    private var lastLockedContentHeight: CGFloat = 0 // 上次锁定时的内容高度
    private var lastKnownViewportHeight: CGFloat = 0 // 上次可见区域高度
    private var shouldMaintainBottomOnNextLayout = false // 下次布局时强制贴底

    // MARK: - 数据缓存
    private var lastAppliedMessageIDs: [UUID] = [] // 上次应用的消息 ID 列表
    private var lastRenderedMessages: [ChatMessage] = [] // 上次渲染的消息
    
    // MARK: - 键盘 & 手势
    private nonisolated(unsafe) var keyboardObservers: [NSObjectProtocol] = [] // 键盘监听
    private weak var backgroundTapGestureRecognizer: UITapGestureRecognizer? // 空白点击收起键盘

    // MARK: - 依赖注入（ViewModel / Store / 工具）
    weak var stateStore: ChatStateStore?
    weak var detailViewModel: ChatDetailViewModel?
    weak var aiSettingsViewModel: AISettingsViewModel?
    var knowledgeDependencies: KnowledgeFeatureDependencies?
    weak var knowledgeViewModel: KnowledgeLibraryViewModel?
    weak var uiStateStore: ChatMessageUIStateStore?
    weak var speechHelper: ChatSpeechHelper?
    weak var memberContextStore: MemberContextStore?
    weak var navigationCoordinator: ChatMessageNavigationCoordinator?
    var taskManager: TaskManager?
    var logger: Logger?
    var actionState: ChatMessageActionState?
    var conversationAppearance: ChatConversationAppearancePreferences = .default
    
    // MARK: - 回调
    var onCommand: ((ConversationListCommand) -> Void)?
    weak var refreshHandler: (any ConversationMessageListRefreshHandling)? // 下拉刷新

    // MARK: - 刷新控件
    private var refreshControl: UIRefreshControl?
    private var isLoadingMoreFlag: Bool = false // 加载中状态

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        // 1. 创建布局 + CollectionView
        let layout = Self.makeCompositionalLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.delegate = self
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .interactive // 互动模式收起键盘
        view.addSubview(cv)
        
        // 铺满全屏
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: view.topAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        collectionView = cv

        // 2. 下拉刷新
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        cv.refreshControl = refresh
        refreshControl = refresh

        // 3. 空白点击收起键盘
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        cv.addGestureRecognizer(tapGesture)
        backgroundTapGestureRecognizer = tapGesture

        // 4. 键盘监听 + 数据源配置
        registerForKeyboardNotifications()
        configureDataSource()
    }

    // 注销监听
    deinit {
        for observer in keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 切换新会话时重置所有状态
    func resetForNewThread() {
        lastAppliedMessageIDs = []
        lastScrollToBottomRequestGeneration = 0
        lastRenderedMessages = []
        userDragging = false
        hasUserInteractedSinceThreadOpen = false
        bottomViewportLockActive = false
        lastLockedContentHeight = 0
        lastKnownViewportHeight = 0
        shouldMaintainBottomOnNextLayout = false
    }

    /// 视图布局完成（键盘/旋转/分屏 后触发）
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewportHeight = currentViewportHeight()
        let viewportChanged = abs(viewportHeight - lastKnownViewportHeight) > 0.5
        lastKnownViewportHeight = viewportHeight
        
        // 视口变化时，保持贴底
        if viewportChanged, shouldMaintainBottomOnNextLayout {
            shouldMaintainBottomOnNextLayout = false
            lastLockedContentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
            scrollToBottom(animated: false, force: true)
        }
        
        maintainBottomViewportLockIfNeeded()
    }

    // MARK: - 下拉刷新
    @objc private func handleRefresh() {
        guard let refreshHandler else {
            refreshControl?.endRefreshing()
            return
        }
        Task {
            await refreshHandler.refreshMessageList()
            await MainActor.run {
                self.refreshControl?.endRefreshing()
            }
        }
    }

    // MARK: - 核心：应用消息列表（增量更新 UI）
    /// 外部调用：传入最新消息，进行增量刷新
    func apply(threadID: UUID, payload: ConversationListApplyPayload) {
        guard let collectionView else { return }
        isLoadingMoreFlag = payload.isLoadingMoreMessages
        let messages = payload.messages
        let hasMoreMessages = payload.hasMoreMessages
        let shouldForceScrollToBottom = payload.scrollToBottomRequestGeneration != lastScrollToBottomRequestGeneration
        lastScrollToBottomRequestGeneration = payload.scrollToBottomRequestGeneration
        if shouldForceScrollToBottom {
            shouldMaintainBottomOnNextLayout = true
        }
        
        // 未交互时 → 自动贴底
        bottomViewportLockActive = payload.lockBottomViewport && hasUserInteractedSinceThreadOpen == false
        
        // 构建更新计划（diff 算法：新增/更新/删除/ prepend）
        let previousForPlan = payload.forceFullListRediff ? [] : lastRenderedMessages
        let updatePlan = ConversationUpdateBuilder.plan(previous: previousForPlan, current: messages)
        
        // 记录当前是否贴底（用于新增消息后判断是否继续贴底）
        let wasPinnedToBottom = ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView)
        // 顶部插入消息时，记录锚点（防止跳动）
        let topAnchor = updatePlan.hasPrependedItems ? captureTopAnchor() : nil

        // 构建 Item ID 列表
        var items: [UUID] = []
        if hasMoreMessages {
            items.append(ConversationListLayoutConstants.loadMoreRowUUID) // 加载更多行
        }
        for m in messages {
            items.append(m.clientMessageID)
        }

        // 构建消息映射表
        var lookup: [UUID: ChatMessage] = [:]
        for m in messages {
            lookup[m.clientMessageID] = m
        }
        messageLookup = lookup

        // 缓存最后渲染数据
        lastAppliedMessageIDs = messages.map(\.clientMessageID)
        lastRenderedMessages = messages

        // 构建 Diffable 快照
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        
        // 需要刷新的行（流式更新）
        let reloadableIDs = updatePlan.reloadedItemIDs.filter { snapshot.indexOfItem($0) != nil }
        if !reloadableIDs.isEmpty {
            snapshot.reloadItems(reloadableIDs)
        }

        // 应用快照
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.collectionView.layoutIfNeeded()
            
            // 策略：主动请求贴底 → 底部锁定 → 恢复顶部锚点 → 结构变化贴底 → 流式更新贴底
            if shouldForceScrollToBottom {
                self.scrollToBottom(animated: false, force: true)
            } else if self.bottomViewportLockActive {
                self.maintainBottomViewportLockIfNeeded(force: true)
            } else if updatePlan.hasPrependedItems, let topAnchor {
                self.restoreTopAnchor(topAnchor)
            } else if updatePlan.kind == .structural {
                if updatePlan.hasAppendedItems && wasPinnedToBottom {
                    self.scrollToBottom(animated: false, force: false)
                }
            } else if reloadableIDs.isEmpty == false {
                if ScrollAnchorPolicy.shouldFollowStream(collectionView: self.collectionView, userDragging: self.userDragging) {
                    self.scrollToBottom(animated: false, force: false)
                }
            }
        }
    }

    // MARK: - 顶部锚点（顶部加载历史消息时保持屏幕不动）
    /// 捕获当前顶部锚点
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

    /// 恢复顶部锚点（不跳动）
    private func restoreTopAnchor(_ anchor: ScrollAnchor) {
        guard let indexPath = dataSource.indexPath(for: anchor.itemID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return
        }
        let targetY = attributes.frame.minY - anchor.offsetFromTop
        setContentOffsetYClamped(targetY)
    }

    /// 单个 SwiftUI hosting cell 内部高度变化时，保持用户当前阅读位置。
    private func performHeightChangingUpdate(affectedItemID: UUID, _ update: @escaping () -> Void) {
        guard let collectionView else {
            update()
            return
        }

        let anchor = captureTopAnchor()
        let wasPinnedToBottom = ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView)
        let wasBottomLocked = bottomViewportLockActive
        let oldContentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let oldContentOffsetY = collectionView.contentOffset.y

        update()
        collectionView.collectionViewLayout.invalidateLayout()

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates(nil) { [weak self] _ in
                self?.restoreViewportAfterHeightChange(
                    affectedItemID: affectedItemID,
                    anchor: anchor,
                    wasPinnedToBottom: wasPinnedToBottom,
                    wasBottomLocked: wasBottomLocked,
                    oldContentHeight: oldContentHeight,
                    oldContentOffsetY: oldContentOffsetY
                )
            }
            collectionView.layoutIfNeeded()
        }

        restoreViewportAfterHeightChange(
            affectedItemID: affectedItemID,
            anchor: anchor,
            wasPinnedToBottom: wasPinnedToBottom,
            wasBottomLocked: wasBottomLocked,
            oldContentHeight: oldContentHeight,
            oldContentOffsetY: oldContentOffsetY
        )

        DispatchQueue.main.async { [weak self] in
            self?.restoreViewportAfterHeightChange(
                affectedItemID: affectedItemID,
                anchor: anchor,
                wasPinnedToBottom: wasPinnedToBottom,
                wasBottomLocked: wasBottomLocked,
                oldContentHeight: oldContentHeight,
                oldContentOffsetY: oldContentOffsetY
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.restoreViewportAfterHeightChange(
                affectedItemID: affectedItemID,
                anchor: anchor,
                wasPinnedToBottom: wasPinnedToBottom,
                wasBottomLocked: wasBottomLocked,
                oldContentHeight: oldContentHeight,
                oldContentOffsetY: oldContentOffsetY
            )
        }
    }

    private func restoreViewportAfterHeightChange(
        affectedItemID: UUID,
        anchor: ScrollAnchor?,
        wasPinnedToBottom: Bool,
        wasBottomLocked: Bool,
        oldContentHeight: CGFloat,
        oldContentOffsetY: CGFloat
    ) {
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()

        if wasBottomLocked {
            maintainBottomViewportLockIfNeeded(force: true)
            return
        }

        if wasPinnedToBottom {
            scrollToBottom(animated: false, force: true)
            return
        }

        guard let anchor else { return }
        let newContentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let heightDelta = newContentHeight - oldContentHeight
        if anchor.itemID == affectedItemID, anchor.offsetFromTop < -1 {
            setContentOffsetYClamped(oldContentOffsetY + heightDelta)
        } else {
            restoreTopAnchor(anchor)
        }
    }

    private func setContentOffsetYClamped(_ y: CGFloat) {
        let minY = -collectionView.adjustedContentInset.top
        let maxY = max(
            minY,
            collectionView.collectionViewLayout.collectionViewContentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom
        )
        collectionView.setContentOffset(CGPoint(x: 0, y: min(max(y, minY), maxY)), animated: false)
    }

    // MARK: - 滚动到底部
    private func scrollToBottom(animated: Bool, force: Bool) {
        guard let collectionView else { return }
        let n = collectionView.numberOfItems(inSection: 0)
        guard n > 0 else { return }
        
        // 非强制：只有原本就在底部才滚动
        if !force && !ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView) {
            return
        }
        
        let indexPath = IndexPath(item: n - 1, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }

    /// 维持底部锁定（AI 流式回复专用）
    private func maintainBottomViewportLockIfNeeded(force: Bool = false) {
        guard bottomViewportLockActive, !hasUserInteractedSinceThreadOpen else { return }
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        
        guard force || abs(contentHeight - lastLockedContentHeight) > 0.5 else { return }
        lastLockedContentHeight = contentHeight
        scrollToBottom(animated: false, force: true)
    }

    /// 计算可见视口高度（减去安全区 + 内边距）
    private func currentViewportHeight() -> CGFloat {
        let visibleHeight = collectionView.bounds.height
            - collectionView.adjustedContentInset.top
            - collectionView.adjustedContentInset.bottom
        return max(0, visibleHeight)
    }

    // MARK: - 键盘监听
    private func registerForKeyboardNotifications() {
        let center = NotificationCenter.default
        keyboardObservers = [
            // 键盘即将改变 frame
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.prepareForKeyboardViewportChange()
            },
            // 键盘即将隐藏
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.prepareForKeyboardViewportChange()
            }
        ]
    }

    /// 键盘变化前：标记需要保持贴底
    private func prepareForKeyboardViewportChange() {
        guard let collectionView else { return }
        if bottomViewportLockActive || ScrollAnchorPolicy.isPinnedToBottom(collectionView: collectionView) {
            shouldMaintainBottomOnNextLayout = true
        }
    }

    // MARK: - 空白点击收起键盘
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, view.window != nil, isKeyboardVisible else { return }
        KeyboardDismissHelper.dismissKeyboard()
    }

    /// 判断键盘是否弹出
    private var isKeyboardVisible: Bool {
        view.window?.firstResponder != nil
    }

    // MARK: - UICollectionViewDelegate
    /// 开始拖拽：用户已交互 → 停止自动贴底
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userDragging = true
        hasUserInteractedSinceThreadOpen = true
        bottomViewportLockActive = false
    }

    /// 结束拖拽
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            userDragging = false
        }
    }

    /// 滚动停止
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userDragging = false
    }

    /// 即将显示 Cell
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // 底部锁定强化
        if bottomViewportLockActive, indexPath.item == collectionView.numberOfItems(inSection: 0) - 1 {
            maintainBottomViewportLockIfNeeded(force: true)
        }
        
        // 滑到“加载更多”行 → 触发加载
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        if item == ConversationListLayoutConstants.loadMoreRowUUID {
            onCommand?(.loadMore)
        }
    }

    // MARK: - 手势代理：过滤不需要响应的点击（如按钮、输入框）
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === backgroundTapGestureRecognizer, isKeyboardVisible else { return false }
        return touch.view?.enclosingKeyboardDismissExemptView == nil
    }

    // MARK: - 布局：Compositional Layout
    private static func makeCompositionalLayout() -> UICollectionViewLayout {
        // 自适应高度消息 cell
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
        section.interGroupSpacing = 12 // 消息间距
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
        
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - 数据源配置
    private func configureDataSource() {
        // UIKit 包裹 SwiftUI Cell
        let registration = UICollectionView.CellRegistration<ConversationHostingCell, UUID> { [weak self] cell, _, itemID in
            guard let self else { return }
            cell.configure(parent: self, content: self.hostedContent(for: itemID))
        }

        // DataSource
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(
            collectionView: collectionView,
            cellProvider: { collectionView, indexPath, itemID in
                collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: itemID)
            }
        )
    }

    // MARK: - SwiftUI 内容构建
    @ViewBuilder
    private func hostedContent(for itemID: UUID) -> some View {
        // 加载更多行
        if itemID == ConversationListLayoutConstants.loadMoreRowUUID {
            ConversationLoadMoreRow(isLoading: isLoadingMoreFlag)
        }
        // 消息行
        else {
            if let msg = messageLookup[itemID],
               let stateStore = stateStore,
               let detailViewModel = detailViewModel,
               let aiSettingsViewModel = aiSettingsViewModel,
               let knowledgeDependencies = knowledgeDependencies,
               let knowledgeViewModel = knowledgeViewModel,
               let uiStateStore = uiStateStore,
               let speechHelper = speechHelper,
               let memberContextStore = memberContextStore,
               let navigationCoordinator = navigationCoordinator,
               let actionState = actionState,
               let taskManager = taskManager,
               let logger = logger
            {
                let threadID = msg.threadID
                let allVisibleMessages = stateStore.conversationListItems(for: threadID)
                    .filter { uiStateStore.isDeleted($0.id) == false }
                
                // 消息行 SwiftUI 组件
                ChatConversationMessageRow(
                    threadID: threadID,
                    message: msg,
                    visibleMessages: allVisibleMessages,
                    stateStore: stateStore,
                    detailViewModel: detailViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    knowledgeDependencies: knowledgeDependencies,
                    knowledgeViewModel: knowledgeViewModel,
                    uiStateStore: uiStateStore,
                    speechHelper: speechHelper,
                    memberContextStore: memberContextStore,
                    navigationCoordinator: navigationCoordinator,
                    actionState: actionState,
                    conversationAppearance: conversationAppearance,
                    taskManager: taskManager,
                    logger: logger,
                    onHeightChangingUpdate: { [weak self] update in
                        self?.performHeightChangingUpdate(affectedItemID: msg.clientMessageID, update)
                    }
                )
                .id(msg.clientMessageID)
            } else {
                Color.clear.frame(height: 1)
            }
        }
    }
}

private extension UIView {
    var enclosingKeyboardDismissExemptView: UIView? {
        sequence(first: self, next: \.superview).first {
            $0 is UIControl || $0 is UITextField || $0 is UITextView
        }
    }
}

private extension UIWindow {
    var firstResponder: UIResponder? {
        firstResponder(in: self)
    }

    func firstResponder(in root: UIView) -> UIResponder? {
        if root.isFirstResponder {
            return root
        }
        for subview in root.subviews {
            if let responder = firstResponder(in: subview) {
                return responder
            }
        }
        return nil
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
