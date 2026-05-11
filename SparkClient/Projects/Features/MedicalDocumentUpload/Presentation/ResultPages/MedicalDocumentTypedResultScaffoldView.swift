import SwiftUI

/// 各识别结果页面的统一骨架，保持交互一致。
struct MedicalDocumentTypedResultScaffoldView: View {
    let pageTitle: String
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card(title: pageTitle, value: "识别类型：\(kindLabel)")
                card(title: "OCR 原文", value: output.envelope.rawOCRText)
                card(title: "抽取 JSON", value: output.extractedJSON)
                card(title: "提交 Payload 预览", value: output.payloadPreview)

                if let saveReceipt {
                    card(title: "保存状态", value: "成功，记录ID：\(saveReceipt.recordID)")
                }

                HStack(spacing: 12) {
                    Button("返回") {
                        onBack()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onSave()
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("提交保存").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var kindLabel: String {
        switch output.envelope.typeResolution.kind {
        case .auto:
            return "自动识别"
        case .caseDocument:
            return "病例"
        case .healthExamReport:
            return "体检"
        case .medicalReport:
            return "医疗报告"
        case .prescription:
            return "处方"
        case .medicationPlan:
            return "用药"
        case .medicineBox:
            return "药品"
        }
    }

    private func card(title: String, value: String) -> some View {
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
