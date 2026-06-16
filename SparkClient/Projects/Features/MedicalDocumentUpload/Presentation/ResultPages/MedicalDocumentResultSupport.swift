import SwiftUI

import SwiftUI

/// 医疗文档结果分组卡片
///
/// 支持：
/// - 标题 / 副标题
/// - SF Symbols 图标
/// - Badge 标签
/// - 操作按钮
/// - 自定义内容
/// - 内容折叠/展开
///
/// 折叠功能特点：
/// - 可配置是否启用折叠
/// - 可配置默认是否折叠
/// - 点击 Header 区域自动展开/收起
/// - 自动显示 Chevron 指示箭头
struct MedicalDocumentResultSectionCard<Content: View>: View {

    // MARK: - 基础配置

    /// 卡片标题
    let title: String

    /// 卡片副标题
    let subtitle: String?

    /// 左侧图标
    let systemImage: String

    /// 主题色
    var tintColor: Color = Color(uiColor: .systemBlue)

    /// 右上角 Badge
    var badgeText: String?

    /// 操作按钮标题
    var actionTitle: String?

    /// 操作按钮点击事件
    var action: (() -> Void)?

    // MARK: - 折叠配置

    /// 是否启用折叠功能
    ///
    /// true：
    /// - 显示折叠箭头
    /// - 点击 Header 可展开/收起
    ///
    /// false：
    /// - 永远展示内容
    /// - 不显示折叠箭头
    var enableCollapse: Bool = false

    /// 默认是否折叠
    ///
    /// 仅在 enableCollapse = true 时生效
    var defaultCollapsed: Bool = false

    /// 折叠模块标识；配合 `expandedSectionIDs` 在预校验定位时强制展开。
    var collapseSectionID: String?

    /// 由结果页维护的已展开模块集合。
    var expandedSectionIDs: Binding<Set<String>>?

    // MARK: - 内容

    /// 卡片内容区域
    @ViewBuilder var content: Content

    // MARK: - State

    /// 当前折叠状态
    @State private var isCollapsed: Bool = false

    // MARK: - Init

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tintColor: Color = Color(uiColor: .systemBlue),
        badgeText: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        enableCollapse: Bool = false,
        defaultCollapsed: Bool = false,
        collapseSectionID: String? = nil,
        expandedSectionIDs: Binding<Set<String>>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tintColor = tintColor
        self.badgeText = badgeText
        self.actionTitle = actionTitle
        self.action = action
        self.enableCollapse = enableCollapse
        self.defaultCollapsed = defaultCollapsed
        self.collapseSectionID = collapseSectionID
        self.expandedSectionIDs = expandedSectionIDs
        self.content = content()

        // 初始化默认折叠状态
        self._isCollapsed = State(initialValue: defaultCollapsed)
    }

    private var isForceExpanded: Bool {
        guard let collapseSectionID, let expandedSectionIDs else { return false }
        return expandedSectionIDs.wrappedValue.contains(collapseSectionID)
    }

    private var showsContent: Bool {
        enableCollapse == false || isCollapsed == false || isForceExpanded
    }

    // MARK: - Body

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            headerView

            if showsContent {
                content
                    .transition(
                        .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(16)
        .id(collapseSectionID)

        // 卡片背景
        .background(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(.regularMaterial)
        )

        // 卡片边框
        .overlay(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.08),
                lineWidth: 1
            )
        )

        // 卡片阴影
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 12,
            x: 0,
            y: 4
        )

        // 折叠动画
        .animation(
            .spring(response: 0.25, dampingFraction: 0.9),
            value: isCollapsed
        )
    }

    // MARK: - Header

    private var headerView: some View {

        HStack(alignment: .top, spacing: 10) {

            // 左侧图标
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tintColor)
                .symbolRenderingMode(.hierarchical)

            // 标题区域
            VStack(alignment: .leading, spacing: 2) {

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                // 副标题
                if let subtitle, subtitle.isEmpty == false {

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Badge
            if let badgeText, badgeText.isEmpty == false {

                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                        .fill(Color(uiColor: .secondarySystemFill))
                    )
            }

            // 操作按钮
            if let actionTitle, let action {

                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }

            // 折叠箭头
            if enableCollapse {

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                    // 旋转箭头
                    .rotationEffect(
                        .degrees(showsContent ? 0 : -90)
                    )
            }
        }

        // 扩大点击区域
        .contentShape(Rectangle())

        // 点击 Header 切换折叠状态
        .onTapGesture {

            guard enableCollapse else {
                return
            }

            if showsContent {
                if let collapseSectionID {
                    expandedSectionIDs?.wrappedValue.remove(collapseSectionID)
                }
                isCollapsed = true
            } else {
                isCollapsed = false
            }
        }
    }
}

struct MedicalDocumentResultInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MedicalDocumentLocalAttachmentItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let displayName: String
    let mimeType: String?

    init(file: MedicalUploadLocalFile) {
        self.id = file.id
        self.fileURL = file.url
        self.displayName = file.displayName
        self.mimeType = file.mimeType
    }

    var previewInput: FilePreviewInput {
        FilePreviewInput(
            id: id,
            fileURL: fileURL,
            displayName: displayName,
            mimeType: mimeType,
            utTypeIdentifier: nil
        )
    }

    var symbolName: String {
        let ext = (displayName as NSString).pathExtension.lowercased()
        if mimeType?.contains("image") == true || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return "photo"
        }
        if mimeType?.contains("pdf") == true || ext == "pdf" {
            return "doc.richtext"
        }
        return "doc"
    }

    var tintColor: Color {
        let ext = (displayName as NSString).pathExtension.lowercased()
        if mimeType?.contains("pdf") == true || ext == "pdf" {
            return Color(uiColor: .systemRed)
        }
        if mimeType?.contains("image") == true || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) {
            return Color(uiColor: .systemBlue)
        }
        return Color(uiColor: .systemIndigo)
    }
}

extension Array where Element == MedicalDocumentLocalAttachmentItem {
    /// 排除已关联到具体业务条目的附件，仅保留未关联项。
    func excludingAssociatedIDs(_ associatedIDs: Set<UUID>) -> [MedicalDocumentLocalAttachmentItem] {
        guard associatedIDs.isEmpty == false else { return self }
        return filter { associatedIDs.contains($0.id) == false }
    }
}

extension PrescriptionRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        var ids = Set(attachmentFileIds)
        for plan in medicationPlans ?? [] {
            ids.formUnion(plan.attachmentFileIds)
            if let box = plan.medicineBox {
                ids.formUnion(box.attachmentFileIds)
            }
        }
        return ids
    }
}

extension CaseRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        var ids = Set(attachmentFileIds)
        if let symptom {
            ids.formUnion(symptom.attachmentFileIds)
        }
        if let visit {
            ids.formUnion(visit.attachmentFileIds)
        }
        if let surgery {
            ids.formUnion(surgery.attachmentFileIds)
        }
        for report in examinationReports ?? [] {
            ids.formUnion(report.attachmentFileIds)
        }
        for prescription in prescriptions ?? [] {
            ids.formUnion(prescription.associatedAttachmentFileIDs)
        }
        for followUp in followUps ?? [] {
            ids.formUnion(followUp.attachmentFileIds)
        }
        return ids
    }
}

extension Array where Element == MedicalReportRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        Set(flatMap(\.attachmentFileIds))
    }
}

extension Array where Element == MedicationPlanRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        Set(flatMap(\.attachmentFileIds))
    }
}

extension Array where Element == MedicineBoxRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        Set(flatMap(\.attachmentFileIds))
    }
}

/// 识别结果页底部：仅展示尚未关联到具体业务条目的源文件附件。
struct MedicalDocumentUnlinkedAttachmentsSectionView: View {
    let attachments: [MedicalDocumentLocalAttachmentItem]
    var tintColor: Color = Color(uiColor: .systemTeal)

    @State private var selectedPreview: FilePreviewInput?
    @State private var previewIndex: Int = 0

    var body: some View {
        if attachments.isEmpty {
            EmptyView()
        } else {
            MedicalDocumentResultSectionCard(
                title: L10n.text("medical.upload.result.attachments.title"),
                subtitle: L10n.text("medical.upload.result.attachments.unlinked.subtitle"),
                systemImage: "paperclip",
                tintColor: tintColor,
                badgeText: String(
                    format: L10n.text("medical.upload.result.attachments.count"),
                    locale: .current,
                    attachments.count
                )
            ) {
                VStack(spacing: 8) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selectedPreview = item.previewInput
                            previewIndex = index
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .unifiedFilePreview(
                isPresented: Binding(
                    get: { selectedPreview != nil },
                    set: { isPresented in
                        if isPresented == false {
                            selectedPreview = nil
                        }
                    }
                ),
                inputs: attachments.map(\.previewInput),
                startIndex: previewIndex
            )
        }
    }

    private func row(_ item: MedicalDocumentLocalAttachmentItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 40, height: 40)
                Image(systemName: item.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct MedicalDocumentAttachmentAssociationSheet: View {
    let title: String
    let localAttachments: [MedicalDocumentLocalAttachmentItem]
    let selectedIDs: [UUID]
    let onSubmit: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDSet: Set<UUID>
    @State private var selectedPreview: FilePreviewInput?
    @State private var previewIndex: Int = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    init(
        title: String,
        localAttachments: [MedicalDocumentLocalAttachmentItem],
        selectedIDs: [UUID],
        onSubmit: @escaping ([UUID]) -> Void
    ) {
        self.title = title
        self.localAttachments = localAttachments
        self.selectedIDs = selectedIDs
        self.onSubmit = onSubmit
        _selectedIDSet = State(initialValue: Set(selectedIDs))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if localAttachments.isEmpty {
                    Text("暂无可关联附件")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(localAttachments.enumerated()), id: \.element.id) { index, item in
                            attachmentCard(item)
                                .onAppear {
                                    if selectedIDSet.contains(item.id) && previewIndex == 0 {
                                        previewIndex = index
                                    }
                                }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.done")) {
                        let orderedIDs = localAttachments.map(\.id).filter { selectedIDSet.contains($0) }
                        onSubmit(orderedIDs)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .unifiedFilePreview(
            isPresented: Binding(
                get: { selectedPreview != nil },
                set: { isPresented in
                    if isPresented == false {
                        selectedPreview = nil
                    }
                }
            ),
            inputs: localAttachments.map(\.previewInput),
            startIndex: previewIndex
        )
    }

    private func attachmentCard(_ item: MedicalDocumentLocalAttachmentItem) -> some View {
        let isSelected = selectedIDSet.contains(item.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(item.id)
            } label: {
                ZStack(alignment: .topTrailing) {
                    thumbnail(item)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85), isSelected ? Color.accentColor : Color.black.opacity(0.45))
                        .padding(6)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Text(item.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    selectedPreview = item.previewInput
                    if let index = localAttachments.firstIndex(where: { $0.id == item.id }) {
                        previewIndex = index
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func thumbnail(_ item: MedicalDocumentLocalAttachmentItem) -> some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            ZStack {
                if item.previewInput.isImage {
                    LocalFileImageThumbnail(url: item.fileURL)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: min(size * 0.3, 32)))
                            .foregroundStyle(item.tintColor)
                        Text(item.displayName)
                            .font(.system(size: min(size * 0.11, 11)))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: size, height: size)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .frame(width: size, height: size)
            .background(Color(uiColor: .tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected(item.id) ? Color.accentColor : Color(uiColor: .separator), lineWidth: isSelected(item.id) ? 2 : 0.5)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func toggle(_ id: UUID) {
        if selectedIDSet.contains(id) {
            selectedIDSet.remove(id)
        } else {
            selectedIDSet.insert(id)
        }
    }

    private func isSelected(_ id: UUID) -> Bool {
        selectedIDSet.contains(id)
    }
}
