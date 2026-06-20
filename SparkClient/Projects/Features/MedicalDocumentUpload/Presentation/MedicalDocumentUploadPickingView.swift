import SwiftUI

// MARK: - 选文件主界面

/// 医疗文档上传流程中的「选文件」界面。
///
/// **职责**
/// - 仅负责展示与交互：成员信息、报告类型、已选文件摘要、缩略图网格、继续添加、提示文案、底部清空/开始识别。
/// - 业务状态与识别流水线由 `MedicalDocumentUploadViewModel` 持有；本视图通过 `@ObservedObject` 读取/回写。
///
/// **布局约定**（与 Health `MedicalUploadGridView` 对齐，便于两端体验一致）
/// - 垂直滚动区：成员卡片 → 报告类型菜单式选择器 →（有文件时）绿色摘要条 → 三列方形预览 → 虚线添加按钮 → 提示卡。
/// - 存在已选文件时，底部固定栏显示「清空」与「开始识别」，并为滚动内容预留底部内边距避免被遮挡。
///
/// **无障碍**
/// - 报告类型控件使用 `accessibilityLabel`，拼接当前选项的本地化名称。
struct MedicalDocumentUploadPickingView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel

    /// 是否展示系统级文件预览 Sheet（由 `UnifiedFilePreview` 承载）。
    @State private var showPreviewSheet = false
    /// 当前预览项在 `selectedFiles` 中的下标；需与 `showPreviewSheet` 同步使用，避免越界。
    @State private var previewIndex = 0

    /// 已选文件中判定为图片类型的数量（依赖 `FilePreviewInput.isImage`，与 UTType/后缀推断一致）。
    private var imageCount: Int {
        viewModel.selectedFiles.map(\.previewInput).filter(\.isImage).count
    }

    /// 非图片文件数量（如 PDF 等），用于摘要角标「N 个文件」。
    private var documentCount: Int {
        viewModel.selectedFiles.count - imageCount
    }

    /// 是否存在任意待识别文件；用于控制摘要条、底部栏显隐。
    private var hasFiles: Bool {
        viewModel.selectedFiles.isEmpty == false
    }

    var body: some View {
        ZStack {
            // 与系统「分组列表」页常用的底色一致，避免纯白刺眼并适配深色模式。
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        memberCard
                        MedicalDocumentKindCategoryPicker(selection: $viewModel.selectedKind)

                        if hasFiles {
                            selectedFilesSummaryCard
                        }

                        filePreviewGrid

                        continueAddButton

                        tipsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    // 预留给底部固定栏的高度，避免最后一项被工具栏遮挡。
                    .padding(.bottom, 100)
                }

                if hasFiles {
                    VStack(spacing: 0) {
                        Divider()
                        bottomActionBar
                    }
                    .background(Color(uiColor: .systemBackground))
                }
            }
        }
        .unifiedFilePreview(
            isPresented: $showPreviewSheet,
            files: viewModel.selectedFiles,
            startIndex: previewIndex
        )
    }

    // MARK: - 当前成员

    /// 展示首页上下文中的就诊成员；若未选择则显示本地化占位文案。
    /// 使用二级背景色与分隔线描边，与「报告类型」卡片的层级感区分不大但可读性足够。
    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("medical.upload.current_member"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.selectedMemberName ?? L10n.text("medical.upload.member.not_selected"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 已选文件摘要条

    /// 绿色渐变背景 + 角标：提示用户已选规模；图片/文档分开计数，与 Health 端摘要语义一致。
    private var selectedFilesSummaryCard: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(.systemGreen))
                    .font(.system(size: 20))
                Text(L10n.text("medical.upload.picking.summary.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            HStack(spacing: 8) {
                if imageCount > 0 {
                    MedicalUploadSummaryBadge(
                        text: String(
                            format: L10n.text("medical.upload.picking.image_count"),
                            locale: .current,
                            imageCount
                        )
                    )
                }
                if documentCount > 0 {
                    MedicalUploadSummaryBadge(
                        text: String(
                            format: L10n.text("medical.upload.picking.document_count"),
                            locale: .current,
                            documentCount
                        )
                    )
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGreen).opacity(0.12),
                    Color(.systemMint).opacity(0.10)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(.systemGreen).opacity(0.35),
                            Color(.systemMint).opacity(0.30)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 预览网格

    /// 三列 `LazyVGrid`：与 Health 方形缩略图一致；点击打开统一预览，角标按钮删除并回调 ViewModel。
    private var filePreviewGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(Array(viewModel.selectedFiles.enumerated()), id: \.element.id) { index, file in
                MedicalDocumentFilePreviewSquareCard(
                    item: file.previewInput,
                    onPreview: {
                        previewIndex = index
                        showPreviewSheet = true
                    },
                    onDelete: {
                        viewModel.removeFile(id: file.id)
                    }
                )
            }
        }
    }

    // MARK: - 继续添加

    /// 虚线边框按钮：内部为 `Menu`，统一使用多选文件入口。
    private var continueAddButton: some View {
        MedicalDocumentFilePickerMenu(
            buttonContent: {
                dashedAddFilesLabel
            },
            onFilesSelected: { files in
                viewModel.setSelectedFiles(viewModel.selectedFiles + files)
            }
        )
    }

    /// 与 `MedicalDocumentFilePickerMenu` 的 label 共用；样式为 project accent + 虚线描边。
    private var dashedAddFilesLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
            Text(L10n.text("medical.upload.picking.add_files"))
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - 提示卡片

    /// 静态提示列表：文案整段放入 `Localizable.strings`，避免在代码里拆分 emoji 导致翻译困难。
    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.tipLocalizationKeys, id: \.self) { key in
                Text(L10n.text(key))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 提示语对应的本地化 Key 列表（顺序即展示顺序）。
    private static let tipLocalizationKeys: [String] = [
        "medical.upload.picking.tip.auto_type",
        "medical.upload.picking.tip.formats"
    ]

    // MARK: - 底部操作栏

    /// 左侧 1/3「清空」仅移除本地与 ViewModel 中的已选列表；右侧 2/3「开始识别」受 `canStartRecognition` 约束（成员 + 非空文件）。
    private var bottomActionBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 12) {
                Button {
                    viewModel.setSelectedFiles([])
                } label: {
                    Text(L10n.text("medical.upload.picking.clear"))
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(uiColor: .separator), lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .frame(width: (geometry.size.width - 12 - 32) / 3)

                Button {
                    viewModel.startRecognitionTask()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text(L10n.text("medical.upload.start"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(.systemGreen),
                                Color(.systemTeal)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Color(.systemGreen).opacity(0.28), radius: 8, x: 0, y: 4)
                }
                .disabled(viewModel.canStartRecognition == false)
                .frame(width: (geometry.size.width - 12 - 32) * 2 / 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(uiColor: .systemBackground)
                    .shadow(color: Color.primary.opacity(0.08), radius: 10, x: 0, y: -2)
            )
        }
        .frame(height: 80)
    }
}

// MARK: - 报告类型（Health 分类条样式）

/// 使用 `Menu` 展开所有 `MedicalDocumentKind`；展示层样式对齐 Health 的「文档类别」大按钮（图标槽 + 双行标题 + chevron）。
private struct MedicalDocumentKindCategoryPicker: View {
    @Binding var selection: MedicalDocumentKind

    var body: some View {
        Menu {
            ForEach(MedicalDocumentKind.allCases, id: \.self) { kind in
                Button {
                    selection = kind
                } label: {
                    kindMenuRow(kind: kind, selected: selection == kind)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selection.iconSystemName)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("medical.upload.picking.report_type"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(selection.localizedPickerLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
            String(
                format: L10n.text("medical.upload.picking.a11y.report_type"),
                locale: .current,
                selection.localizedPickerLabel
            )
        )
    }

    /// 下拉菜单内的行：左侧 SF Symbol 与 Health 一致；右侧对当前选中项显示 checkmark。
    private func kindMenuRow(kind: MedicalDocumentKind, selected: Bool) -> some View {
        Label {
            HStack {
                Text(kind.localizedPickerLabel)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        } icon: {
            Image(systemName: kind.iconSystemName)
        }
    }
}

// MARK: - MedicalDocumentKind 展示辅助

/// 仅用于本模块 UI：图标仍用 SF Symbol 常量（跨语言一致），文案走 `L10n`。
private extension MedicalDocumentKind {
    /// 下拉按钮与菜单项上显示的标签（随系统语言切换）。
    var localizedPickerLabel: String {
        switch self {
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        case .caseDocument:
            return L10n.text("medical.upload.kind.case")
        case .healthExamReport:
            return L10n.text("medical.upload.kind.health_exam")
        case .medicalReport:
            return L10n.text("medical.upload.kind.medical_report")
        case .prescription:
            return L10n.text("common.prescription")
        case .medicationPlan:
            return L10n.text("common.medicationPlan")
        case .medicineBox:
            return L10n.text("home.medical.list.medicine_box.title", fallback: "药品")
        }
    }

    /// 与 Health `MedicalUploadCategoryPicker` 中各类别图标语义对齐，便于用户快速扫视。
    var iconSystemName: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .caseDocument: return "list.clipboard.fill"
        case .healthExamReport: return "heart.text.square.fill"
        case .medicalReport: return "doc.text.fill"
        case .prescription: return "pills.fill"
        case .medicationPlan: return "capsule.fill"
        case .medicineBox: return "shippingbox.fill"
        }
    }
}

// MARK: - 摘要角标

/// 摘要条右侧小 pill：二级背景 + 分隔线边框，与系统「辅助信息」层级接近。
private struct MedicalUploadSummaryBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
