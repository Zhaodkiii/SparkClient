import SwiftUI

struct CaseMemberInfoSectionView: View {
    let memberID: Int?
    let draft: CaseRecognitionDraft
    var validationIssues: [MedicalPreSubmitValidationIssue] = []

    private var caseCardHasError: Bool {
        validationIssues.contains { $0.fieldKey.hasPrefix("medical_case.") }
    }

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: "成员信息",
            subtitle: "识别到的成员与主档信息",
            systemImage: "person.text.rectangle",
            badgeText: caseCardHasError
                ? L10n.text("medical.upload.presubmit.badge.needs_fix")
                : "\(draft.infoDensityCount)项"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(
                    title: "成员 ID",
                    value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected")
                )
                MedicalValidatedResultInfoLine(
                    title: "病例标题",
                    value: draft.title,
                    issues: validationIssues.issues(forFieldKey: "medical_case.title")
                )
                MedicalDocumentResultInfoLine(title: "就诊医院", value: draft.hospitalName ?? "")
                MedicalValidatedResultInfoLine(
                    title: "就诊年龄",
                    value: draft.ageAtVisit ?? "",
                    issues: validationIssues.issues(forFieldKey: "medical_case.age_at_visit")
                )
                MedicalValidatedResultInfoLine(
                    title: "就诊日期",
                    value: draft.occurredAt ?? "",
                    issues: validationIssues.issues(forFieldKey: "medical_case.occurred_at")
                )
                MedicalDocumentResultInfoLine(title: "病情摘要", value: draft.summary ?? "")
            }
        }
    }
}
