import SwiftUI

struct CaseMemberInfoSectionView: View {
    let memberID: Int?
    let draft: CaseRecognitionDraft

    var body: some View {
        MedicalDocumentResultSectionCard(
            title: "成员信息",
            subtitle: "识别到的成员与主档信息",
            systemImage: "person.text.rectangle",
            badgeText: "\(draft.infoDensityCount)项"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MedicalDocumentResultInfoLine(title: "成员 ID", value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected"))
                MedicalDocumentResultInfoLine(title: "病例标题", value: draft.title)
                MedicalDocumentResultInfoLine(title: "就诊医院", value: draft.hospitalName ?? "")
                MedicalDocumentResultInfoLine(title: "就诊年龄", value: draft.ageAtVisit ?? "")
                MedicalDocumentResultInfoLine(title: "就诊日期", value: draft.occurredAt ?? "")
                MedicalDocumentResultInfoLine(title: "病情摘要", value: draft.summary ?? "")
            }
        }
    }
}
