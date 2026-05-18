import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 用药执行中心页面（主视图）
/// 展示用户当日/选定日期的用药计划、待执行用药、已完成用药记录，支持日期切换、用药记录提交
struct MedicationExecutionCenterPage: View {
    // MARK: - 外部传入依赖数据
    /// 远程用药计划列表
    let medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    /// 远程药箱列表
    let medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    /// 初始加载的用药记录
    let initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    /// 家庭成员ID
    let memberID: Int?
    /// 医疗查询接口
    let medicalQueryAPI: SparkMedicalQueryAPI
    /// 医疗工作流接口
    let workflowAPI: SparkMedicalWorkflowAPI
    /// 文件传输服务
    let fileTransferService: FileTransferService
    /// 通知客户端
    let notificationClient: any NotificationClient
    /// 日志工具
    let logger: Logger

    // MARK: - 环境与状态变量
    /// 页面关闭环境变量
    @Environment(\.dismiss) private var dismiss
    /// 当前选中的日期
    @State private var selectedDate = Date()
    /// 用药记录数据源
    @State private var records: [SparkMedicalSyncAPI.RemoteMedicationRecord]
    /// 是否正在加载数据
    @State private var isLoading = false
    /// 是否正在保存数据
    @State private var isSaving = false
    /// 用药记录弹窗上下文
    @State private var logSheet: MedicationExecutionLogSheetContext?
    /// 日期条每个日期项的位置信息
    @State private var dateStripItemFrames: [String: CGRect] = [:]
    /// 日期条可视区域
    @State private var dateStripViewport: CGRect = .zero
    /// 日期条指示器位置
    @State private var dateStripIndicatorFrame: CGRect = .zero

    /// 日期条是否正在拖拽
    @State private var isDateStripDragging = false
    /// 日期条自动对齐任务
    @State private var dateStripSettleTask: Task<Void, Never>?
    /// 日期条对齐操作抑制截止时间
    @State private var dateStripSettleSuppressedUntil: Date?

    // MARK: - 常量配置
    /// 日历实例
    private let calendar = Calendar.current
    /// 日志模块
    private let logModule = LogModule.home
    /// 日期条坐标空间名称
    private let dateStripCoordinateSpace = "MedicationExecutionDateStrip"
    /// 日期条单个日期项宽度
    private let dateStripItemWidth: CGFloat = 56

    // MARK: - 初始化方法
    init(
        medicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        memberID: Int?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        workflowAPI: SparkMedicalWorkflowAPI,
        fileTransferService: FileTransferService,
        notificationClient: any NotificationClient,
        logger: Logger
    ) {
        self.medicationPlans = medicationPlans
        self.medicineBoxes = medicineBoxes
        self.initialRecords = initialRecords
        self.memberID = memberID
        self.medicalQueryAPI = medicalQueryAPI
        self.workflowAPI = workflowAPI
        self.fileTransferService = fileTransferService
        self.notificationClient = notificationClient
        self.logger = logger
        // 初始化State变量
        _records = State(initialValue: initialRecords)
    }

    // MARK: - 计算属性
    /// 当前选中日期的当天起始时间
    private var selectedDayStart: Date {
        calendar.startOfDay(for: selectedDate)
    }

    /// 日期条展示的日期列表（前后各45天）
    private var dateStripDays: [MedicationExecutionDateItem] {
        (-45...45).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: Date()) else {
                return nil
            }
            return MedicationExecutionDateItem(date: calendar.startOfDay(for: date), calendar: calendar)
        }
    }

    /// 当日所有计划用药剂量
    private var scheduledDoses: [MedicationExecutionDose] {
        MedicationExecutionPlanner.scheduledDoses(
            plans: medicationPlans,
            medicineBoxes: medicineBoxes,
            records: records,
            on: selectedDayStart,
            calendar: calendar
        )
    }

    /// 待执行的用药剂量
    private var pendingDoses: [MedicationExecutionDose] {
        scheduledDoses.filter { $0.isCompleted == false }
    }

    /// 已完成的用药剂量
    private var completedDoses: [MedicationExecutionDose] {
        scheduledDoses.filter(\.isCompleted)
    }

    /// 按需用药计划（无固定提醒时间）
    private var asNeededPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        medicationPlans
            .filter { MedicationExecutionPlanner.isPlanActive($0, on: selectedDayStart, calendar: calendar) }
            .filter { $0.reminderTimes.isEmpty }
            .sorted { $0.drugName < $1.drugName }
    }

    /// 按ID分组的药箱字典
    private var medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox] {
        Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
    }

    // MARK: - 主视图内容
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dateHeader       // 日期标题栏
                dateStrip        // 横向日期选择条
                recordSection    // 用药记录区域
                // 有已完成记录时展示
                if completedDoses.isEmpty == false {
                    completedSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        // 设置坐标空间，用于日期条布局计算
        .coordinateSpace(name: dateStripCoordinateSpace)
        .onPreferenceChange(MedicationExecutionDateStripIndicatorFramePreferenceKey.self) { frame in
            dateStripIndicatorFrame = frame
        }
        // 页面背景
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        // 导航栏配置
        .navigationTitle("用药")
        .navigationBarTitleDisplayMode(.inline)
        
        // 加载/保存时展示进度指示器
        .overlay {
            if isLoading || isSaving {
                ProgressView()
                    .tint(.accentColor)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        // 用药记录弹窗
        .sheet(item: $logSheet) { context in
            MedicationExecutionLogSheet(
                context: context,
                isSaving: isSaving,
                fileTransferService: fileTransferService,
                onCancel: { logSheet = nil },
                onDone: { selections in
                    Task { await saveSelections(selections, for: context.doses) }
                }
            )
        }
        // 页面出现时加载当日记录
        .task {
            await loadRecords(for: selectedDayStart, preferInitialRecords: true)
        }
        // 选中日期变化时重新加载记录
        .onChange(of: selectedDayStart) { newValue in
            Task { await loadRecords(for: newValue, preferInitialRecords: false) }
        }
    }

    // MARK: - 子视图：日期标题栏
    /// 顶部日期标题（展示年月日+星期/今天）
    private var dateHeader: some View {
        VStack(spacing: 12) {
            Text(Self.longDateTitle(selectedDayStart, calendar: calendar))
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)

            // 下拉指示器箭头
            Image(systemName: "arrowtriangle.down.fill")
                .font(.title3)
                .foregroundStyle(.primary)
                .medicationExecutionDateStripIndicatorFrame(in: dateStripCoordinateSpace)

            Divider()
        }
    }

    // MARK: - 子视图：横向日期选择条
    /// 可滑动、自动对齐的日期选择条
    private var dateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(dateStripDays) { item in
                        Button {
                            selectedDate = item.date
                            impact(style: .light)
                        } label: {
                            MedicationExecutionDateDot(
                                date: item.date,
                                isSelected: calendar.isDate(item.date, inSameDayAs: selectedDayStart),
                                progress: MedicationExecutionPlanner.progress(
                                    plans: medicationPlans,
                                    medicineBoxes: medicineBoxes,
                                    records: records,
                                    on: item.date,
                                    calendar: calendar
                                ),
                                calendar: calendar
                            )
                        }
                        .id(item.id)
                        .medicationExecutionDateStripItemFrame(id: item.id, in: dateStripCoordinateSpace)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, dateStripSidePadding)
                .padding(.vertical, 4)
            }
            .medicationExecutionDateStripViewportFrame(in: dateStripCoordinateSpace)
            // 监听日期项布局变化
            .onPreferenceChange(MedicationExecutionDateStripItemFramePreferenceKey.self) { frames in
                dateStripItemFrames = frames
                scheduleDateStripSettleEvaluation(proxy: proxy)
            }
            // 监听可视区域变化
            .onPreferenceChange(MedicationExecutionDateStripViewportFramePreferenceKey.self) { frame in
                dateStripViewport = frame
                scheduleDateStripSettleEvaluation(proxy: proxy)
            }
            // 拖拽手势
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in
                        isDateStripDragging = true
                    }
                    .onEnded { _ in
                        isDateStripDragging = false
                        scheduleDateStripSettleEvaluation(proxy: proxy)
                    }
            )
            // 页面出现时滚动到今日
            .onAppear {
                dateStripSettleSuppressedUntil = Date().addingTimeInterval(0.45)
                proxy.scrollTo(MedicationExecutionDateItem.id(for: selectedDayStart, calendar: calendar), anchor: .center)
            }
            // 选中日期变化时自动滚动居中
            .onChange(of: selectedDayStart) { newValue in
                if isDateStripDragging == false {
                    dateStripSettleSuppressedUntil = Date().addingTimeInterval(0.45)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        proxy.scrollTo(MedicationExecutionDateItem.id(for: newValue, calendar: calendar), anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, -20)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedDayStart)
    }

    /// 日期条左右内边距（保证居中显示）
    private var dateStripSidePadding: CGFloat {
        guard dateStripViewport.width > 0 else { return 20 }
        return max(20, (dateStripViewport.width - dateStripItemWidth) / 2)
    }

    /// 日期条对齐目标中心点X坐标
    private var dateStripSnapTargetX: CGFloat {
         guard dateStripIndicatorFrame.width > 0 else { return dateStripViewport.midX }
         return dateStripIndicatorFrame.midX
     }
    
    /// 延迟执行日期条自动对齐（惯性滚动结束后）
    private func scheduleDateStripSettleEvaluation(proxy: ScrollViewProxy) {
        if isDateStripDragging { return }
        dateStripSettleTask?.cancel()
        dateStripSettleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            if isDateStripDragging { return }
            if let until = dateStripSettleSuppressedUntil, until > Date() { return }
            applyDateStripSnapToCenterItem(proxy: proxy, playHaptics: true)
            dateStripSettleTask = nil
        }
    }

    /// 执行日期条自动对齐到中心日期项
    private func applyDateStripSnapToCenterItem(proxy: ScrollViewProxy, playHaptics: Bool) {
        isDateStripDragging = false
        guard dateStripViewport.width > 0, dateStripItemFrames.isEmpty == false else { return }

        dateStripSettleSuppressedUntil = Date().addingTimeInterval(0.4)

        let centerX = dateStripSnapTargetX
        // 找到距离中心点最近的日期项
        guard let snappedID = dateStripItemFrames.min(by: {
            abs($0.value.midX - centerX) < abs($1.value.midX - centerX)
        })?.key else {
            return
        }

        // 更新选中日期
        if let snappedItem = dateStripDays.first(where: { $0.id == snappedID }),
           calendar.isDate(snappedItem.date, inSameDayAs: selectedDayStart) == false {
            if playHaptics {
                impact(style: .light)
            }
            selectedDate = snappedItem.date
        } else {
            // 无日期变化，仅滚动居中
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                proxy.scrollTo(snappedID, anchor: .center)
            }
        }
    }

    // MARK: - 子视图：用药记录区域
    /// 待执行用药 + 按需用药模块
    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("记录")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            // 无待执行任务时展示完成卡片
            if pendingDoses.isEmpty {
                MedicationExecutionAllDoneCard()
            } else {
                // 按时间分组展示待执行用药
                VStack(spacing: 14) {
                    ForEach(MedicationExecutionPlanner.groupByTime(pendingDoses), id: \.timeText) { group in
                        MedicationExecutionPendingCard(
                            timeText: group.timeText,
                            doses: group.doses,
                            fileTransferService: fileTransferService,
                            onAdd: {
                                // 打开记录弹窗
                                logSheet = MedicationExecutionLogSheetContext(
                                    title: "记录于 \(group.timeText)",
                                    date: selectedDayStart,
                                    doses: group.doses
                                )
                            }
                        )
                    }
                }
            }

            // 有按需用药计划时展示
            if asNeededPlans.isEmpty == false {
                MedicationExecutionAsNeededCard {
                    let doses = asNeededPlans.enumerated().map { index, plan in
                        MedicationExecutionPlanner.asNeededDose(
                            plan: plan,
                            medicineBoxesByID: medicineBoxesByID,
                            date: selectedDayStart,
                            sequence: index + 1,
                            calendar: calendar
                        )
                    }
                    logSheet = MedicationExecutionLogSheetContext(title: "全部药品", date: selectedDayStart, doses: doses)
                }
            }
        }
    }

    // MARK: - 子视图：已完成用药区域
    /// 已完成用药记录列表
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("已记录")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                let groups = MedicationExecutionPlanner.groupByTime(completedDoses)
                ForEach(groups, id: \.timeText) { group in
                    MedicationExecutionCompletedGroup(group: group)
                    if group.timeText != groups.last?.timeText {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }

    // MARK: - 数据加载
    /// 加载指定日期的用药记录
    @MainActor
    private func loadRecords(for day: Date, preferInitialRecords: Bool) async {
        guard let memberID else { return }
        // 优先使用初始记录（今日）
        if preferInitialRecords && calendar.isDateInToday(day) && initialRecords.isEmpty == false {
            records = initialRecords
            return
        }

        isLoading = true
        defer { isLoading = false } // 方法结束后自动关闭loading

        do {
            let start = calendar.startOfDay(for: day)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            // 请求接口获取记录
            records = try await medicalQueryAPI.listMedicationRecords(
                memberID: memberID,
                scheduledFrom: start,
                scheduledTo: end
            )
        } catch {
            // 错误提示与日志
            notificationClient.error(error.localizedDescription, title: "加载服药记录失败", source: "medical.medication_execution.load")
            logger.warning("用药执行中心加载记录失败 error=\(error.localizedDescription)", module: logModule)
        }
    }

    // MARK: - 数据保存
    /// 保存用户选择的用药状态
    @MainActor
    private func saveSelections(
        _ selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus],
        for doses: [MedicationExecutionDose]
    ) async {
        guard isSaving == false else { return }
        let selectedDoses = doses.filter { selections[$0.id] != nil }
        // 无选中项直接关闭弹窗
        guard selectedDoses.isEmpty == false else {
            logSheet = nil
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // 批量保存选中的用药记录
            for dose in selectedDoses {
                guard let status = selections[dose.id] else { continue }
                let saved = try await saveDose(dose, status: status)
                upsertRecord(saved) // 更新本地数据源
            }
            logSheet = nil
            impact(style: .medium) // 震动反馈
        } catch {
            notificationClient.error(error.localizedDescription, title: "记录用药失败", source: "medical.medication_execution.save")
            logger.warning("用药执行中心保存状态失败 error=\(error.localizedDescription)", module: logModule)
        }
    }

    /// 保存单条用药剂量记录（新增/更新）
    private func saveDose(
        _ dose: MedicationExecutionDose,
        status: MedicationDoseLogStatus
    ) async throws -> SparkMedicalSyncAPI.RemoteMedicationRecord {
        let takenAt = status == .taken ? MedicalDateCoding.encodeISO8601(Date()) : nil
        let actualDose = status == .taken ? dose.plannedDose : ""

        // 已有记录 → 更新
        if let record = dose.record {
            let payload = MedicationRecordUpdatePayload(
                takenAt: takenAt,
                status: status.rawValue,
                actualDose: actualDose,
                notes: record.notes,
                extra: record.extra ?? [:]
            )
            return try await workflowAPI.update(
                SparkMedicalSyncAPI.RemoteMedicationRecord.self,
                kind: .medicationRecords,
                id: record.id,
                body: payload
            )
        }

        // 无记录 → 新增
        let payload = MedicationRecordCreatePayload(
            member: dose.plan.member,
            plan: dose.plan.id,
            scheduledAt: MedicalDateCoding.encodeISO8601(dose.scheduledAt),
            takenAt: takenAt,
            status: status.rawValue,
            plannedDose: dose.plannedDose,
            actualDose: actualDose,
            doseSequence: dose.doseSequence,
            timezone: TimeZone.current.identifier,
            notes: "",
            extra: [:]
        )
        return try await workflowAPI.create(
            SparkMedicalSyncAPI.RemoteMedicationRecord.self,
            kind: .medicationRecords,
            body: payload
        )
    }

    /// 更新本地记录数组（存在则更新，不存在则添加）
    private func upsertRecord(_ record: SparkMedicalSyncAPI.RemoteMedicationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }

    // MARK: - 工具方法
    /// 震动反馈
    private func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    /// 格式化日期标题（x月x日 星期几/今天）
    private static func longDateTitle(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        if calendar.isDateInToday(date) {
            return "\(month)月\(day)日 今天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return "\(month)月\(day)日 \(formatter.string(from: date))"
    }
}

private enum MedicationDoseLogStatus: String, Equatable {
    case taken
    case skipped

    var title: String {
        switch self {
        case .taken: return "已用药"
        case .skipped: return "已跳过"
        }
    }

    var symbolName: String {
        switch self {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        }
    }
}

private struct MedicationExecutionDateItem: Identifiable, Equatable {
    let date: Date
    let id: String

    init(date: Date, calendar: Calendar) {
        self.date = date
        self.id = Self.id(for: date, calendar: calendar)
    }

    static func id(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct MedicationExecutionDateStripItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct MedicationExecutionDateStripViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct MedicationExecutionDateStripIndicatorFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    func medicationExecutionDateStripItemFrame(id: String, in coordinateSpace: String) -> some View {
        overlay {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MedicationExecutionDateStripItemFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(coordinateSpace))]
                )
            }
        }
    }
    func medicationExecutionDateStripIndicatorFrame(in coordinateSpace: String) -> some View {
            background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MedicationExecutionDateStripIndicatorFramePreferenceKey.self,
                        value: proxy.frame(in: .named(coordinateSpace))
                    )
                }
            }
        }

    func medicationExecutionDateStripViewportFrame(in coordinateSpace: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MedicationExecutionDateStripViewportFramePreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpace))
                )
            }
        }
    }
}

private struct MedicationExecutionLogSheetContext: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let doses: [MedicationExecutionDose]
}

private struct MedicationExecutionDose: Identifiable, Equatable {
    let id: String
    let plan: SparkMedicalSyncAPI.RemoteMedicationPlan
    let scheduledAt: Date
    let plannedDose: String
    let doseSequence: Int
    let record: SparkMedicalSyncAPI.RemoteMedicationRecord?
    let imageAttachment: SparkMedicalSyncAPI.RemoteManagedFile?

    var status: String {
        record?.status ?? "scheduled"
    }

    var isCompleted: Bool {
        status == "taken" || status == "skipped"
    }

    var displayName: String {
        plan.drugName.trimmedNonEmpty ?? "未命名药品"
    }

    var specificationText: String {
        let doseUnit = plan.doseUnit.trimmedNonEmpty
        return ["药片", doseUnit].compactMap { $0 }.joined(separator: "，")
    }

    var instructionText: String {
        let time = MedicationExecutionPlanner.timeText(for: scheduledAt)
        return "\(time) 用药： \(plannedDose)"
    }
}

private struct MedicationExecutionTimeGroup: Equatable {
    let timeText: String
    let doses: [MedicationExecutionDose]
}

private enum MedicationExecutionPlanner {
    static func scheduledDoses(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        on day: Date,
        calendar: Calendar
    ) -> [MedicationExecutionDose] {
        let medicineBoxesByID = Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
        let recordsBySlot = Dictionary(grouping: recordsForDay(records, day: day, calendar: calendar)) {
            slotKey(planID: $0.plan, scheduledAt: $0.scheduledAt, calendar: calendar)
        }
        let plansByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })

        var doses = plans
            .filter { isPlanActive($0, on: day, calendar: calendar) }
            .flatMap { plan in
                plan.reminderTimes.enumerated().compactMap { index, reminder -> MedicationExecutionDose? in
                    guard let scheduledAt = scheduledDate(on: day, timeText: reminder.time, calendar: calendar) else {
                        return nil
                    }
                    let key = slotKey(planID: plan.id, scheduledAt: scheduledAt, calendar: calendar)
                    return MedicationExecutionDose(
                        id: key,
                        plan: plan,
                        scheduledAt: scheduledAt,
                        plannedDose: plan.dosePerTime.trimmedNonEmpty ?? plan.doseUnit,
                        doseSequence: index + 1,
                        record: recordsBySlot[key]?.sorted { $0.updatedAt > $1.updatedAt }.first,
                        imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
                    )
                }
            }

        let generatedKeys = Set(doses.map(\.id))
        for record in recordsForDay(records, day: day, calendar: calendar) {
            let key = slotKey(planID: record.plan, scheduledAt: record.scheduledAt, calendar: calendar)
            guard generatedKeys.contains(key) == false, let plan = plansByID[record.plan] else { continue }
            doses.append(
                MedicationExecutionDose(
                    id: key,
                    plan: plan,
                    scheduledAt: record.scheduledAt,
                    plannedDose: record.plannedDose,
                    doseSequence: record.doseSequence,
                    record: record,
                    imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
                )
            )
        }

        return doses.sorted {
            if $0.scheduledAt == $1.scheduledAt {
                return $0.displayName < $1.displayName
            }
            return $0.scheduledAt < $1.scheduledAt
        }
    }

    static func asNeededDose(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox],
        date: Date,
        sequence: Int,
        calendar: Calendar
    ) -> MedicationExecutionDose {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        let scheduledAt = calendar.date(from: components) ?? now
        return MedicationExecutionDose(
            id: "as-needed-\(plan.id)-\(Int(scheduledAt.timeIntervalSince1970))",
            plan: plan,
            scheduledAt: scheduledAt,
            plannedDose: plan.dosePerTime.trimmedNonEmpty ?? plan.doseUnit,
            doseSequence: sequence,
            record: nil,
            imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
        )
    }

    static func groupByTime(_ doses: [MedicationExecutionDose]) -> [MedicationExecutionTimeGroup] {
        let grouped = Dictionary(grouping: doses) { timeText(for: $0.scheduledAt) }
        return grouped.keys.sorted().map { key in
            MedicationExecutionTimeGroup(timeText: key, doses: grouped[key] ?? [])
        }
    }

    static func progress(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        on day: Date,
        calendar: Calendar
    ) -> Double {
        let doses = scheduledDoses(plans: plans, medicineBoxes: medicineBoxes, records: records, on: day, calendar: calendar)
        guard doses.isEmpty == false else { return 0 }
        return Double(doses.filter(\.isCompleted).count) / Double(doses.count)
    }

    static func isPlanActive(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan, on day: Date, calendar: Calendar) -> Bool {
        guard plan.status == "active" else { return false }
        let dayStart = calendar.startOfDay(for: day)
        let planStart = calendar.startOfDay(for: plan.startDate)
        guard planStart <= dayStart else { return false }
        if let endDate = plan.endDate, calendar.startOfDay(for: endDate) < dayStart {
            return false
        }

        switch plan.frequencyType {
        case "every_n_days":
            let interval = max(plan.everyNDays ?? 1, 1)
            let days = calendar.dateComponents([.day], from: planStart, to: dayStart).day ?? 0
            return days >= 0 && days % interval == 0
        case "weekly":
            let weekday = chineseWeekdayNumber(for: dayStart, calendar: calendar)
            return plan.weeklyWeekdays.contains(weekday)
        default:
            return true
        }
    }

    static func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func recordsForDay(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        day: Date,
        calendar: Calendar
    ) -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
    }

    private static func scheduledDate(on day: Date, timeText: String, calendar: Calendar) -> Date? {
        let parts = timeText.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func slotKey(planID: Int, scheduledAt: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        return "\(planID)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
    }

    private static func chineseWeekdayNumber(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func imageAttachment(
        for plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    ) -> SparkMedicalSyncAPI.RemoteManagedFile? {
        MedicationImageAttachmentResolver.firstImageAttachment(
            for: plan,
            medicineBoxesByID: medicineBoxesByID
        )
    }
}

private struct MedicationExecutionDateDot: View {
    let date: Date
    let isSelected: Bool
    let progress: Double
    let calendar: Calendar

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(weekdayText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)

            statusMarker
        }
        .frame(height: 44)
        .frame(width: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var clampedProgress: Double {
        max(0, min(progress, 1))
    }

    @ViewBuilder
    private var statusMarker: some View {
        if isSelected {
            Circle()
                .fill(Color(uiColor: .systemTeal))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground).opacity(0.9), lineWidth: 2)
                        .padding(4)
                }
        } else {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .systemGray4), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(Color(uiColor: .systemTeal), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity(clampedProgress > 0 ? 1 : 0)
            }
            .frame(width: 18, height: 18)
        }
    }

    private var accessibilityText: String {
        let status: String
        if isSelected {
            status = "已选中"
        } else if clampedProgress > 0 {
            status = "有执行进度"
        } else {
            status = "无执行进度"
        }

        return "\(weekdayText)，\(Self.accessibilityDateFormatter.string(from: date))，\(status)"
    }

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private struct MedicationExecutionPendingCard: View {
    let timeText: String
    let doses: [MedicationExecutionDose]
    let fileTransferService: FileTransferService
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(timeText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                ForEach(doses) { dose in
                    HStack(spacing: 12) {
                        MedicationImageGlyph(
                            seed: dose.plan.id,
                            attachment: dose.imageAttachment,
                            fileTransferService: fileTransferService
                        )
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dose.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(dose.plannedDose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加用药记录")
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct MedicationExecutionAsNeededCard: View {
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text("按需用药")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .imageScale(.medium)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .background(
            Color(uiColor: .systemTeal).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct MedicationExecutionAllDoneCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("已记录今天的所有定时用药")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct MedicationExecutionCompletedGroup: View {
    let group: MedicationExecutionTimeGroup

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(group.timeText)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.doses) { dose in
                    HStack(spacing: 8) {
                        Image(systemName: dose.status == "taken" ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(dose.status == "taken" ? Color(uiColor: .systemTeal) : Color(uiColor: .systemGray))
                        Text(dose.status == "taken" ? dose.displayName : "\(dose.displayName)（已跳过）")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 14)
    }
}

private struct MedicationExecutionLogSheet: View {
    let context: MedicationExecutionLogSheetContext
    let isSaving: Bool
    let fileTransferService: FileTransferService
    let onCancel: () -> Void
    let onDone: ([MedicationExecutionDose.ID: MedicationDoseLogStatus]) -> Void

    @State private var selections: [MedicationExecutionDose.ID: MedicationDoseLogStatus] = [:]

    private var canSubmit: Bool {
        selections.isEmpty == false && isSaving == false
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 16) {
                        ForEach(context.doses) { dose in
                            MedicationExecutionLogDoseCard(
                                dose: dose,
                                fileTransferService: fileTransferService,
                                selection: selections[dose.id],
                                onSelect: { status in
                                    selections[dose.id] = status
                                    impact(style: .light)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    onDone(selections)
                } label: {
                    Text("完成")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            canSubmit ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray3),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(canSubmit == false)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.regularMaterial)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selections)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(Self.dateTitle(context.date))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(context.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("\(context.doses.count)种用药")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    private static func dateTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.month, .day], from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return "\(comps.month ?? 1)月\(comps.day ?? 1)日 \(formatter.string(from: date))"
    }
}

private struct MedicationExecutionLogDoseCard: View {
    let dose: MedicationExecutionDose
    let fileTransferService: FileTransferService
    let selection: MedicationDoseLogStatus?
    let onSelect: (MedicationDoseLogStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                MedicationImageGlyph(
                    seed: dose.plan.id,
                    attachment: dose.imageAttachment,
                    fileTransferService: fileTransferService
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(dose.specificationText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Label {
                        Text(dose.instructionText)
                    } icon: {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                    }
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                statusButton(.skipped)
                statusButton(.taken)
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func statusButton(_ status: MedicationDoseLogStatus) -> some View {
        Button {
            onSelect(status)
        } label: {
            Label(status.title, systemImage: selection == status ? status.symbolName : "")
                .font(.headline.weight(.semibold))
                .foregroundStyle(selection == status ? .white : Color(uiColor: .systemBlue))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    selection == status ? Color(uiColor: .systemBlue) : Color(uiColor: .systemBlue).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MedicationRecordCreatePayload: Encodable {
    let member: Int
    let plan: Int
    let scheduledAt: String
    let takenAt: String?
    let status: String
    let plannedDose: String
    let actualDose: String
    let doseSequence: Int
    let timezone: String
    let notes: String
    let extra: [String: String]

}

private struct MedicationRecordUpdatePayload: Encodable {
    let takenAt: String?
    let status: String
    let actualDose: String
    let notes: String
    let extra: [String: String]

}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

#Preview("Medication Execution Light") {
    CompatibleNavigationContainer {
        MedicationExecutionCenterPage(
            medicationPlans: [],
            medicineBoxes: [],
            initialRecords: [],
            memberID: nil,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
            logger: AppContainer.preview.logger
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Medication Execution Dark") {
    CompatibleNavigationContainer {
        MedicationExecutionCenterPage(
            medicationPlans: [],
            medicineBoxes: [],
            initialRecords: [],
            memberID: nil,
            medicalQueryAPI: AppContainer.preview.backend.medicalQuery,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            fileTransferService: AppContainer.preview.fileTransferService,
            notificationClient: AppContainer.preview.notificationClient,
            logger: AppContainer.preview.logger
        )
    }
    .preferredColorScheme(.dark)
}
