import SwiftUI

/// 病历草稿表单通用容器：标题 + 圆角材质背景，供各 `*FormView` 复用。
struct SparkFormCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}

/// 单行 `TextField`，标签在上、输入在下。
struct SparkFormTextRow: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    init(title: String, text: Binding<String>, placeholder: String = "") {
        self.title = title
        _text = text
        self.placeholder = placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// 多行 `TextEditor`，用于长文本字段。
struct SparkFormTextAreaRow: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat

    init(title: String, text: Binding<String>, minHeight: CGFloat = 88) {
        self.title = title
        _text = text
        self.minHeight = minHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22), lineWidth: 1))
        }
    }
}

extension String {
    /// 空白字符串视为 `nil`，用于草稿字段映射到可选 API 字段。
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
