import SwiftUI

struct DeepTutorMemberProfileCardView: View {
    let payload: DeepTutorMemberProfileBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summaryGrid
            sectionList
            footer
        }
        .padding(16)
        .background(DeepTutorPalette.cardBackground, in: cardShape)
        .overlay {
            cardShape.strokeBorder(DeepTutorPalette.borderColor, lineWidth: 1)
        }
        .deepTutorAskUserCardShadow()
        .padding(.top, 12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cross.case.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: DeepTutorPalette.askUserBadgeSize, height: DeepTutorPalette.askUserBadgeSize)

            VStack(alignment: .leading, spacing: 4) {
                Text("已获取成员医疗资料")
                    .font(.system(size: DeepTutorPalette.askUserHeaderFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(payload.memberName) · \(payload.relationshipText) · \(payload.genderText) · \(payload.ageText)")
                    .font(.system(size: DeepTutorPalette.askUserSubtitleFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
                if let requestedFocus = payload.requestedFocus, requestedFocus.isEmpty == false {
                    Text("关注方向：\(requestedFocus)")
                        .font(.system(size: DeepTutorPalette.askUserSubtitleFontSize))
                        .foregroundStyle(DeepTutorPalette.traceMutedText)
                }
            }
        }
    }

    private var summaryGrid: some View {
        HStack(spacing: 8) {
            metricChip(title: "身高体重", value: payload.bodyMetricsSummary)
            metricChip(title: "体检报告", value: "\(payload.healthExamReportCount)份")
            metricChip(title: "用药计划", value: "\(payload.medicationPlanCount)条")
        }
    }

    private var sectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionRow(title: "基础档案", body: payload.basicProfileSummary)
            sectionRow(title: "健康病史", body: payload.healthHistorySummary)
            sectionRow(title: "生活习惯", body: payload.lifestyleSummary)
            sectionRow(title: "过往体检档案", body: payload.examArchiveSummary)
            sectionRow(title: "风险评估", body: payload.riskAssessmentSummary)

            if payload.sections.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务端分区摘要")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    ForEach(payload.sections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(section.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(DeepTutorPalette.traceMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("来源：SparkService 成员 complete-data 聚合")
                .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
            if let updatedAt = payload.guidanceUpdatedAt {
                Text("资料更新时间：\(dateText(updatedAt))")
                    .font(.system(size: DeepTutorPalette.askUserFooterFontSize))
                    .foregroundStyle(DeepTutorPalette.traceMutedText)
            }
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(DeepTutorPalette.traceMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dateText(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DeepTutorPalette.askUserCardCornerRadius, style: .continuous)
    }
}
