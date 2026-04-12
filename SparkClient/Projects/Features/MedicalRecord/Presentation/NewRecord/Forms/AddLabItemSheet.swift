import SwiftUI

/// 检验报告子项编辑弹层：写入父表单的 `ItemDraft`，项目名为必填。
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

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    private var canSubmit: Bool {
        !draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                SparkFormCard(title: L10n.text("medical_record.forms.lab_item.card_title")) {
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.category"), text: $draft.category)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.subcategory"), text: $draft.subCategory)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.item_name"), text: $draft.itemName)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.result"), text: $draft.resultValue)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.unit"), text: $draft.unit)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.reference_range"), text: $draft.referenceRange)
                    SparkFormTextRow(title: L10n.text("medical_record.forms.field.flag"), text: $draft.flag)
                }
                .padding(16)
            }
            .navigationTitle(L10n.text("medical_record.forms.lab_item.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .sparkFormBottomBar(
                canSubmit: canSubmit,
                saveTitle: L10n.text("medical_record.forms.action.complete"),
                onCancel: {
                    formLog.info("AddLabItemSheet: cancel tapped", module: formLogModule)
                    dismiss()
                },
                onSave: {
                    formLog.info("AddLabItemSheet: submit itemName=\(draft.itemName.prefix(80))", module: formLogModule)
                    onSubmit(draft)
                    dismiss()
                }
            )
        }
    }
}
