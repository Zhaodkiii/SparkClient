import SwiftUI

struct AddLabItemSheet: View {
    struct Draft: Identifiable {
        var id = UUID()
        var category: String = "laboratory"
        var subCategory: String = ""
        var itemName: String = ""
        var resultValue: String = ""
        var unit: String = ""
        var referenceRange: String = ""
        var flag: String = ""
    }

    @Environment(\.dismiss) private var dismiss
    @State var draft: Draft
    let onSubmit: (Draft) -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                SparkFormCard(title: "检验子项") {
                    SparkFormTextRow(title: "分类", text: $draft.category)
                    SparkFormTextRow(title: "子分类", text: $draft.subCategory)
                    SparkFormTextRow(title: "项目", text: $draft.itemName)
                    SparkFormTextRow(title: "结果", text: $draft.resultValue)
                    SparkFormTextRow(title: "单位", text: $draft.unit)
                    SparkFormTextRow(title: "参考范围", text: $draft.referenceRange)
                    SparkFormTextRow(title: "标记", text: $draft.flag)
                }
                .padding(16)
            }
            .navigationTitle("新增检验项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onSubmit(draft)
                        dismiss()
                    }
                    .disabled(draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
