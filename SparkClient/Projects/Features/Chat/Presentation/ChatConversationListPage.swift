import SwiftUI

/// 聊天会话列表页面
///
/// 核心功能：
/// - 展示所有聊天会话列表，支持搜索过滤
/// - 支持新建会话、删除会话、置顶/取消置顶、编辑会话外观（标题/图标/颜色）
/// - 左滑/右滑快捷操作，长按上下文菜单
/// - 启动时自动导航逻辑：5分钟内有活跃会话则自动进入，否则自动新建会话
/// - 无可用模型时提示用户前往设置配置 API Key
struct ChatConversationListPage: View {
    /// 聊天全局状态存储
    @ObservedObject var stateStore: ChatStateStore
    /// 列表页 ViewModel，负责列表数据加载、搜索、会话管理
    @ObservedObject var listViewModel: ChatListViewModel
    /// 详情页 ViewModel，负责消息加载和发送
    @ObservedObject var detailViewModel: ChatDetailViewModel
    /// 知识库功能依赖注入容器
    let knowledgeDependencies: KnowledgeFeatureDependencies
    /// 知识库页面 ViewModel
    @ObservedObject var knowledgeViewModel: KnowledgeLibraryViewModel
    /// 任务管理器，处理后台上传/下载任务
    @ObservedObject var taskManager: TaskManager
    /// 首页 ViewModel
    @ObservedObject var homeViewModel: HomeViewModel
    /// AI 设置 ViewModel，管理模型和 API Key 配置
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    /// 推送适配器，处理通知权限申请
    let pushAdapter: PushAdapter
    /// 引导卡片滑块跳转健康首页的构造器（CHAT-000025）
    /// - Note: 由 App 宿主注入；nil（旧宿主 / 未注入）时滑块降级为纯展示面板，不响应点击跳转
    var guideHomeDestinationBuilder: ChatGuideHomeDestinationBuilder? = nil

    /// 搜索框输入文本
    @State private var searchText = ""
    /// 待导航的会话 ID，用于控制 NavigationLink 自动跳转
    @State private var pendingThreadNavigation: UUID?
    /// 页面是否已完成首次加载，防止重复执行 onAppear 逻辑
    @State private var hasLoaded = false
    /// 是否已处理启动自动导航逻辑，保证只执行一次
    @State private var hasHandledInitialAutoNavigation = false
    /// 是否显示"无可用聊天模型"警告弹窗
    @State private var showNoAvailableChatModelAlert = false
    /// 是否显示 API Key 设置页面
    @State private var showAPIKeysSettingsSheet = false
    /// 是否正在显示会话外观编辑弹窗
    @State private var isEditingThreadAppearance = false
    /// 当前正在编辑的会话 ID
    @State private var editingThreadID: UUID?
    /// 编辑中的会话标题
    @State private var editingTitle: String = ""
    /// 编辑中的会话图标名称
    @State private var editingIconName: String? = nil
    /// 编辑中的会话图标颜色名称
    @State private var editingIconColorName: String? = nil
    /// 拖拽手势防抖标记：一次拖拽手势中仅触发一次收键盘动作
    /// - Note: 避免滚动过程中多次触发键盘收起
    @State private var hasDismissedKeyboardInCurrentDrag = false

    /// 根据搜索文本过滤后的会话列表项
    private var itemsToDisplay: [ChatThreadListItem] {
        listViewModel.search(text: searchText)
    }

    var body: some View {
        List {
            if itemsToDisplay.isEmpty {
                // 空状态视图
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                // 会话列表行
                ForEach(itemsToDisplay) { item in
                    threadRow(item)
                }
            }
        }
        .listStyle(.plain)
        // 对齐主流聊天应用交互：列表滚动时交互式收起键盘
        .chatScrollDismissesKeyboardInteractively()
        .navigationTitle(L10n.text("chat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L10n.text("chat.list.search.placeholder"))
        // 自定义拖拽手势：拖拽开始时立即收起键盘，参考 Signal 交互设计
        // 使用 simultaneousGesture 保证不影响列表本身的滚动手势
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in
                    guard hasDismissedKeyboardInCurrentDrag == false else { return }
                    hasDismissedKeyboardInCurrentDrag = true
                    KeyboardDismissHelper.dismissKeyboard()
                }
                .onEnded { _ in
                    hasDismissedKeyboardInCurrentDrag = false
                }
        )
        .toolbar {
            // 左侧导航栏按钮：知识库入口
            ToolbarItem(placement: .navigationBarLeading) {
                MainNavigationLink {
                    KnowledgeLibraryView(
                        dependencies: knowledgeDependencies,
                        viewModel: knowledgeViewModel
                    )
                } label: {
                    Image(systemName: "backpack.fill")
                }
                .accessibilityLabel(L10n.text("knowledge.library.title"))
            }
            // 右侧导航栏按钮：新建会话
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await createThreadIfAvailable()
                    }
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .accessibilityLabel(L10n.text("chat.thread.new", fallback: "新建对话"))
            }
        }
        // 首次加载任务：只执行一次
        .task {
            guard hasLoaded == false else { return }
            hasLoaded = true
            // 加载列表数据
            await listViewModel.loadForListIfNeeded()
            // 处理启动自动导航
            await handleInitialAutoNavigationIfNeeded()
        }
        // 下拉刷新
        .refreshable {
            await listViewModel.refreshThreads()
        }
        // 无可用模型警告弹窗
        .alert(L10n.text("chat.list.no_available_model.title"), isPresented: $showNoAvailableChatModelAlert) {
            Button(L10n.text("chat.list.no_available_model.action")) {
                showAPIKeysSettingsSheet = true
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("chat.list.no_available_model.message"))
        }
        // API Key 设置弹窗
        .sheet(isPresented: $showAPIKeysSettingsSheet) {
            NavigationView {
                APIKeysSettingsView(viewModel: aiSettingsViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.done")) {
                                showAPIKeysSettingsSheet = false
                            }
                        }
                    }
            }
        }
        // 会话外观编辑弹窗（标题、图标、颜色）
        .sheet(isPresented: $isEditingThreadAppearance) {
            ChatThreadAppearanceEditSheet(
                title: editingTitle,
                iconName: editingIconName,
                iconColorName: editingIconColorName,
                onSave: { title, iconName, iconColorName in
                    guard let id = editingThreadID else { return }
                    Task {
                        await listViewModel.updateThreadAppearance(
                            threadID: id,
                            title: title,
                            iconName: iconName,
                            iconColorName: iconColorName
                        )
                    }
                },
                onCancel: {}
            )
        }
        // 自动导航到会话详情：通过 pendingThreadNavigation 控制
        // 使用 navigationDestination 匹配编程式导航，避免列表中每个 NavigationLink 都提前初始化 ChatView
        .navigationDestination(isPresented: Binding(
            get: { pendingThreadNavigation != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingThreadNavigation = nil
                }
            }
        )) {
            if let threadID = pendingThreadNavigation {
                ChatView(
                    threadID: threadID,
                    stateStore: stateStore,
                    listViewModel: listViewModel,
                    detailViewModel: detailViewModel,
                    knowledgeDependencies: knowledgeDependencies,
                    knowledgeViewModel: knowledgeViewModel,
                    taskManager: taskManager,
                    homeViewModel: homeViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    guideHomeDestinationBuilder: guideHomeDestinationBuilder
                )
                // 进入聊天页时隐藏底部 TabBar
                .hidesMainTabBarWhenPushed()
            }
        }
    }

    /// 列表空状态视图
    ///
    /// 两种状态：
    /// - 正在刷新/首次同步：显示加载指示器和"同步中"提示
    /// - 真正空列表：显示空状态图标、提示文字和"新建对话"按钮
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if listViewModel.isRefreshingEmptyListFallback {
                // 首次加载中状态
                ProgressView()
                Text(L10n.text("chat.list.empty.syncing"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                // 空列表状态
                Image(systemName: "message.circle")
                    .font(.system(size: 52))
                    .foregroundColor(.secondary)
                Text(L10n.text("chat.list.empty.title"))
                    .font(.headline)
                    .foregroundColor(.secondary)
                Button {
                    Task {
                        await createThreadIfAvailable()
                    }
                } label: {
                    Text(L10n.text("chat.list.empty.create"))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }

    /// 单个会话列表行视图
    ///
    /// 包含：
    /// - 左侧自定义图标（支持用户自定义颜色和图标）
    /// - 右侧标题、置顶标记、最新消息时间、最新消息预览
    /// - 长按上下文菜单：编辑、置顶/取消置顶、删除
    /// - 左滑操作：置顶（蓝色）、编辑（绿色）
    /// - 右滑操作：删除（红色，支持全滑动直接删除）
    /// - Parameter item: 会话列表项数据
    @ViewBuilder
    private func threadRow(_ item: ChatThreadListItem) -> some View {
        MainNavigationLink {
            ChatView(
                threadID: item.id,
                stateStore: stateStore,
                listViewModel: listViewModel,
                detailViewModel: detailViewModel,
                knowledgeDependencies: knowledgeDependencies,
                knowledgeViewModel: knowledgeViewModel,
                taskManager: taskManager,
                homeViewModel: homeViewModel,
                aiSettingsViewModel: aiSettingsViewModel,
                guideHomeDestinationBuilder: guideHomeDestinationBuilder
            )
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // 会话图标
                threadIcon(item.thread)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.thread.listDisplayTitle)
                            .font(.headline)
                            .lineLimit(1)
                        // 置顶标记
                        if item.thread.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // 最新消息时间
                        Text(formattedDate(item.latestMessageAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // 最新消息预览，最多两行
                    Text(item.latestMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        // 扩展点击区域到整个行
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        // 长按上下文菜单
        .contextMenu {
            Button {
                beginEditingAppearance(for: item.thread)
            } label: {
                Label(L10n.text("chat.thread.edit", fallback: "编辑"), systemImage: "paintbrush")
            }

            Button {
                Task { await listViewModel.toggleThreadPinned(item.id) }
            } label: {
                Label(
                    item.thread.isPinned
                        ? L10n.text("chat.thread.unpin", fallback: "取消置顶")
                        : L10n.text("chat.thread.pin", fallback: "置顶"),
                    systemImage: item.thread.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive) {
                Task {
                    await listViewModel.deleteThread(item.id)
                }
            } label: {
                Label(L10n.text("common.delete"), systemImage: "trash")
            }
        }
        // 左滑操作：不支持全滑动触发
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // 置顶/取消置顶按钮（蓝色）
            Button {
                Task { await listViewModel.toggleThreadPinned(item.id) }
            } label: {
                Label(
                    item.thread.isPinned
                        ? L10n.text("chat.thread.unpin", fallback: "取消置顶")
                        : L10n.text("chat.thread.pin", fallback: "置顶"),
                    systemImage: item.thread.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(ChatThreadAppearanceResources.color(from: "hlBlue"))

            // 编辑按钮（绿色）
            Button {
                beginEditingAppearance(for: item.thread)
            } label: {
                Label(L10n.text("chat.thread.edit", fallback: "编辑"), systemImage: "paintbrush")
            }
            .tint(ChatThreadAppearanceResources.color(from: "hlGreen"))
        }
        // 右滑操作：支持全滑动直接删除
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task {
                    await listViewModel.deleteThread(item.id)
                }
            } label: {
                Label(L10n.text("common.delete"), systemImage: "trash")
            }
        }

    }

    /// 会话自定义图标视图
    ///
    /// 支持用户自定义图标名称和颜色，未自定义时使用默认气泡图标和主题色
    /// - Parameter thread: 会话对象
    @ViewBuilder
    private func threadIcon(_ thread: ChatThread) -> some View {
        // 图标：优先使用用户自定义，默认气泡图标
        let icon = (thread.iconName?.isEmpty == false ? thread.iconName : nil) ?? "bubble.left.circle"
        // 颜色：优先使用用户自定义，默认主题色
        let colorName = (thread.iconColorName?.isEmpty == false ? thread.iconColorName : nil) ?? "accent"
        let tint = ChatThreadAppearanceResources.color(from: colorName)

        Image(systemName: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 34, height: 34)
            .foregroundStyle(tint)
            .padding(6)
            .background(Circle().fill(.thinMaterial))
    }

    /// 开始编辑会话外观（标题、图标、颜色）
    ///
    /// 初始化编辑状态并弹出编辑 Sheet
    /// - Parameter thread: 要编辑的会话对象
    private func beginEditingAppearance(for thread: ChatThread) {
        editingThreadID = thread.id
        editingTitle = thread.title
        editingIconName = thread.iconName
        editingIconColorName = thread.iconColorName
        isEditingThreadAppearance = true
    }

    /// 创建新会话（如果有可用模型）
    ///
    /// 流程：
    /// 1. 检查是否有可用的聊天模型，无模型则弹出提示
    /// 2. 请求推送权限（如果还未确定）
    /// 3. 调用 ViewModel 创建新会话
    /// 4. 自动导航到新创建的会话
    private func createThreadIfAvailable() async {
        // 模型可用性检查
        guard await detailViewModel.hasAvailableChatModel() else {
            showNoAvailableChatModelAlert = true
            return
        }
        // 异步请求推送权限，不阻塞流程
        pushAdapter.requestAuthorizationIfNotDetermined()
        // 创建新会话
        await listViewModel.createThread()
        guard let threadID = stateStore.selectedThreadID else { return }
        // 导航到新会话
        await navigateToThread(threadID)
    }

    /// 处理应用启动时的自动导航逻辑（仅执行一次）
    ///
    /// 策略：
    /// - 如果当前已有选中会话且有未发送草稿：不自动导航，保留用户编辑状态
    /// - 否则查找 5 分钟内有最新消息的活跃会话，自动进入
    /// - 没有最近活跃会话：自动创建新会话并进入
    private func handleInitialAutoNavigationIfNeeded() async {
        guard hasHandledInitialAutoNavigation == false else { return }
        hasHandledInitialAutoNavigation = true
        // 有草稿时跳过自动导航，避免打断用户
        guard shouldSkipInitialAutoNavigation == false else { return }

        // 优先恢复最近 5 分钟内活跃的会话
        if let activeThreadID = mostRecentActiveThreadID(within: 5 * 60) {
            await navigateToThread(activeThreadID)
            return
        }

        // 无最近活跃会话：自动创建新会话
        await createThreadIfAvailable()
    }

    /// 查找指定时间间隔内有最新消息的最近活跃会话 ID
    /// - Parameter interval: 时间间隔（秒），如 5*60 表示 5 分钟
    /// - Returns: 最近活跃会话 ID，无则返回 nil
    private func mostRecentActiveThreadID(within interval: TimeInterval) -> UUID? {
        let cutoff = Date().addingTimeInterval(-interval)
        // 列表按最新消息排序，第一个满足时间条件的就是最近活跃的
        return stateStore.threadItems.first(where: { $0.latestMessageAt >= cutoff })?.id
    }

    /// 是否应该跳过启动自动导航
    ///
    /// 判断条件：当前选中的会话有未发送的草稿内容，此时跳过自动导航保留用户输入
    private var shouldSkipInitialAutoNavigation: Bool {
        guard let selectedThreadID = stateStore.selectedThreadID else { return false }
        let draft = stateStore.draft(for: selectedThreadID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty == false
    }

    /// 导航到指定会话详情页
    ///
    /// 流程：
    /// 1. 在列表中选中该会话
    /// 2. 预加载消息数据，锁定底部视口保证打开时滚动到底部
    /// 3. 设置 pendingThreadNavigation 触发 NavigationLink 跳转
    /// - Parameter threadID: 要导航到的会话 ID
    private func navigateToThread(_ threadID: UUID) async {
        listViewModel.selectThread(threadID)
        await detailViewModel.loadMessagesIfNeeded(for: threadID, lockBottomViewport: true)
        pendingThreadNavigation = threadID
    }

    /// 格式化消息时间显示
    ///
    /// 规则：
    /// - 今天：显示 HH:mm
    /// - 昨天：显示"昨天"（本地化）
    /// - 更早：显示 MM-dd
    /// - Parameter date: 要格式化的日期
    /// - Returns: 格式化后的时间字符串
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return L10n.text("common.yesterday")
        } else {
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}
