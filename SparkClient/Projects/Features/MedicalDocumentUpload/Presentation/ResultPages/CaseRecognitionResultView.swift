import SwiftUI

/// 病例识别结果页（按模块拆分至 ResultPages/CaseRecognitionResult）
struct CaseRecognitionResultView: View {
    let output: MedicalDocumentTypedExtractionOutput
    let isSaving: Bool
    let saveReceipt: MedicalDocumentSaveReceipt?
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        CaseRecognitionResultContentView(
            output: output,
            isSaving: isSaving,
            saveReceipt: saveReceipt,
            onBack: onBack,
            onSave: onSave
        )
        .navigationTitle("病例")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Case result - Light") {
    CompatibleNavigationContainer {
        CaseRecognitionResultView(
            output: .previewCase,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Case result - Dark") {
    CompatibleNavigationContainer {
        CaseRecognitionResultView(
            output: .previewCase,
            isSaving: false,
            saveReceipt: nil,
            onBack: {},
            onSave: {}
        )
    }
    .preferredColorScheme(.dark)
}

private extension MedicalDocumentTypedExtractionOutput {
    static var previewCase: MedicalDocumentTypedExtractionOutput {
        MedicalDocumentTypedExtractionOutput(
            envelope: MedicalDocumentRecognitionEnvelope(
                memberID: 1,
                sourceFiles: [
                    MedicalUploadLocalFile(
                        url: URL(fileURLWithPath: "/tmp/lab.pdf"),
                        displayName: "血常规报告.pdf",
                        mimeType: "application/pdf"
                    )
                ],
                rawOCRText: "",
                typeResolution: MedicalDocumentTypeResolution(
                    kind: .caseDocument,
                    confidence: 0.93,
                    source: .ai,
                    reason: "命中病例关键词"
                )
            ),
            typedResult: .caseDocument(
                CaseRecognitionDraft(
                    title: "门诊复诊记录",
                    summary: "发热伴咽痛 3 天",
                    diagnosis: "上呼吸道感染",
                    hospitalName: "仁和医院",
                    ageAtVisit: "32",
                    occurredAt: "2026-04-12",
                    symptom: SymptomRecognitionDraft(
                        name: "发热",
                        code: "R50",
                        severity: "中度",
                        startedAt: "2026-04-09",
                        durationValue: "3",
                        durationUnit: "天",
                        bodyPart: "全身",
                        notes: "夜间明显"
                    ),
                    visit: VisitRecognitionDraft(
                        visitType: "门诊",
                        visitedAt: "2026-04-12",
                        department: "呼吸科",
                        doctorName: "王医生",
                        visitNo: "OP-1001",
                        notes: "建议复查"
                    ),
                    surgery: nil,
                    followUps: [
                        FollowUpRecognitionDraft(
                            plannedAt: "2026-04-19",
                            completedAt: nil,
                            status: "待执行",
                            method: "电话",
                            outcome: nil,
                            nextAction: "复查血常规"
                        )
                    ],
                    prescriptionBatches: [
                        PrescriptionRecognitionDraft(
                            medicalCase: 1,
                            prescriberName: "王医生",
                            institutionName: "仁和医院",
                            prescribedAt: "2026-04-12",
                            diagnosis: "上呼吸道感染",
                            batchNo: "RX-1200",
                            status: "active",
                            auditorName: nil,
                            auditedAt: nil,
                            extra: nil,
                            medications: [
                                MedicationPlanRecognitionDraft(
                                    medicineName: "布洛芬缓释胶囊",
                                    medicineType: "止痛退热",
                                    brandName: nil,
                                    dosageForm: "胶囊",
                                    strength: "300mg",
                                    dosePerTime: "1 粒",
                                    doseValue: "1",
                                    doseUnit: "粒",
                                    frequencyCode: "BID",
                                    frequencyType: "daily",
                                    timesPerPeriod: "2",
                                    frequencyText: "每日 2 次",
                                    durationDays: "5",
                                    instructions: "饭后服",
                                    reminderEnabled: false,
                                    reminderTimes: [],
                                    sortOrder: "0",
                                    extra: nil
                                )
                            ]
                        )
                    ],
                    examinationReports: [
                        MedicalReportRecognitionDraft(
                            category: "laboratory",
                            title: "血常规",
                            hospital: "仁和医院",
                            doctor: "李医生",
                            content: "白细胞略高",
                            date: "2026-04-12",
                            details: []
                        )
                    ]
                )
            ),
            extractedJSON: "",
            payloadPreview: ""
        )
    }
}
