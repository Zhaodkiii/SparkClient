import SwiftUI

struct CaseMemberInfoSectionView: View {
    let memberID: Int?
    let draft: CaseRecognitionDraft

    var body: some View {
        CaseSectionCard(
            title: "成员信息",
            subtitle: "识别到的成员与主档信息",
            systemImage: "person.text.rectangle",
            badgeText: "\(draft.infoDensityCount)项"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                CaseInfoLine(title: "成员 ID", value: memberID.map(String.init) ?? L10n.text("medical.upload.member.not_selected"))
                CaseInfoLine(title: "病例标题", value: draft.title)
                CaseInfoLine(title: "就诊医院", value: draft.hospitalName ?? "")
                CaseInfoLine(title: "就诊年龄", value: draft.ageAtVisit ?? "")
                CaseInfoLine(title: "就诊日期", value: draft.occurredAt ?? "")
                CaseInfoLine(title: "病情摘要", value: draft.summary ?? "")
            }
        }
    }
}
