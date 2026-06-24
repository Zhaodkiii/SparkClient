import SwiftUI

/// 编辑模式底部工具栏：布局与 Health `TextEditToolbar` 一致——单行图标 + 右侧 Token，无图标下标题。
/// 业务由 `KnowledgeDocumentEditorViewModel` 注入；本组件不访问 `ModelContext`。
///
/// Health 对应关系：`optimize` → 优化、`translate` → 翻译（`globe` 非 `.circle`）、`ocr` → 取景器、
/// `extra` → 文档/网页、`clear` → `trash.circle`；计数为右侧 `VStack` 右对齐双行。
struct KnowledgeTextEditToolbar: View {
    let characterCount: Int
    let tokenEstimate: Int
    let isBusy: Bool
    let onPolish: () -> Void
    let onTranslate: () -> Void
    let onOCR: () -> Void
    let onImportFile: () -> Void
    /// 展开/收起网页 URL 输入条（Health 在父级用 `extraButtons` 实现）。
    let onToggleWebPanel: () -> Void
    let onClear: () -> Void

    /// 与 Health `TextEditToolbar` 的 `size_30` 一致（`@ScaledMetric` 默认约 36pt）。
    @ScaledMetric(relativeTo: .body) private var size30: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                polishButton
                translateButton
                ocrButton
                documentButton
                webButton
                clearButton
                Spacer(minLength: 8)
                tokenCounter
            }
        }
        .padding(12)
        .disabled(isBusy)
        .opacity(isBusy ? 0.55 : 1)
    }

    // MARK: - 图标按钮（仅 SF Symbol，与 Health 同尺寸、灰色）

    private var polishButton: some View {
        Button(action: onPolish) {
            Image(systemName: "hammer.circle")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.polish"))
    }

    private var translateButton: some View {
        Button(action: onTranslate) {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.translate"))
    }

    private var ocrButton: some View {
        Button(action: onOCR) {
            Image(systemName: "viewfinder.circle")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.ocr"))
    }

    private var documentButton: some View {
        Button(action: onImportFile) {
            Image(systemName: "document.circle")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.document"))
    }

    private var webButton: some View {
        Button(action: onToggleWebPanel) {
            Image(systemName: "link.circle")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.web"))
    }

    private var clearButton: some View {
        Button(action: onClear) {
            Image(systemName: "trash.circle")
                .resizable()
                .scaledToFit()
                .frame(width: size30, height: size30)
                .foregroundColor(Color(.systemGray))
        }
        .buttonStyle(.plain)
        .frame(width: size30, height: size30)
        .accessibilityLabel(L10n.text("knowledge.toolbar.clear"))
    }

    /// 与 Health `tokenCounter()` 一致：右侧两行、caption、灰色。
    private var tokenCounter: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(L10n.format("knowledge.toolbar.chars", characterCount))
                .font(.caption)
                .foregroundColor(.gray)
            Text(L10n.format("knowledge.toolbar.tokens_approx", tokenEstimate))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .accessibilityElement(children: .combine)
    }
}
