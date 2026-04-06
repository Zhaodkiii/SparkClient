import SwiftUI

struct MedicalDocumentUploadResultView: View {
    let result: MedicalDocumentRecognitionResult
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCard(title: "OCR 原文", value: result.rawOCRText)
                sectionCard(title: "抽取 JSON", value: result.extractedJSONString)
                sectionCard(title: "提交 Payload 预览", value: result.serverPayloadPreview ?? "-")

                if let saveReceipt {
                    sectionCard(
                        title: "保存状态",
                        value: "成功，记录 ID: \(saveReceipt.recordID)\n时间: \(saveReceipt.savedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                }

                HStack(spacing: 12) {
                    Button("返回") {
                        onBack()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("提交保存").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sectionCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.body)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}
