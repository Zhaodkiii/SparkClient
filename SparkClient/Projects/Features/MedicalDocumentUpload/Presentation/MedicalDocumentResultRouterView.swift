import SwiftUI

/// 分类型结果页路由：按业务类型跳转到对应页面组件。
struct MedicalDocumentResultRouterView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        switch output.typedResult {
        case .caseDocument(let draft):
            CaseRecognitionResultView(title: draft.title, output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
        case .healthExamReport:
            HealthExamRecognitionResultView(output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
        case .medicalReport:
            MedicalReportRecognitionResultView(output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
        case .prescription:
            PrescriptionRecognitionResultView(output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
        case .medication:
            MedicationRecognitionResultView(output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
        }
    }
}

struct CaseRecognitionResultView: View {
    let title: String
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        TypedResultScaffoldView(pageTitle: "病例识别结果 - \(title)", output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
    }
}

struct HealthExamRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        TypedResultScaffoldView(pageTitle: "体检报告识别结果", output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
    }
}

struct MedicalReportRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        TypedResultScaffoldView(pageTitle: "医疗报告识别结果", output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
    }
}

struct PrescriptionRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        TypedResultScaffoldView(pageTitle: "处方识别结果", output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
    }
}

struct MedicationRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        TypedResultScaffoldView(pageTitle: "用药识别结果", output: output, isSaving: isSaving, saveReceipt: saveReceipt, onBack: onBack, onSave: onSave)
    }
}

private struct TypedResultScaffoldView: View {
    let pageTitle: String
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card(title: pageTitle, value: "识别类型：\(output.envelope.typeResolution.kind.rawValue)")
                card(title: "OCR 原文", value: output.envelope.rawOCRText)
                card(title: "抽取 JSON", value: output.extractedJSON)
                card(title: "提交 Payload 预览", value: output.payloadPreview)
                if let saveReceipt {
                    card(title: "保存状态", value: "成功，记录ID：\(saveReceipt.recordID)")
                }
                HStack(spacing: 12) {
                    Button("返回") { onBack() }.buttonStyle(.bordered)
                    Button {
                        onSave()
                    } label: {
                        if isSaving { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("提交保存").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func card(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value).font(.body).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}
