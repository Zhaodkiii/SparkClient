import Foundation

/// 将 SparkService complete-data 聚合接口结果格式化为 AI 可读的成员医疗资料摘要与扁平元数据。
/// 名称保持中性，供普通 Chat 与 ToolHub 的成员资料工具共用，不依赖任何下线模块类型。
enum MemberProfileFormatter {
    struct AIResult: Sendable {
        let content: String
        let metadata: [String: String]
    }

    @MainActor
    static func makeAIResult(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        requestedFocus: String?
    ) -> AIResult {
        let focus = requestedFocus?.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = makeCardPayload(data: data, requestedFocus: focus)
        let sections = card.sections.map { section in
            "- \(section.title)：\(section.summary)"
        }.joined(separator: "\n")

        let content = """
        已获取成员医疗资料，以下内容来自 SparkService complete-data 聚合接口，可用于后续个性化体检计划制定。

        [成员基础资料]
        - 成员ID：\(card.memberID)
        - 姓名：\(card.memberName)
        - 关系：\(card.relationshipText)
        - 性别：\(card.genderText)
        - 年龄：\(card.ageText)
        - 身高体重：\(card.bodyMetricsSummary)
        - 本次关注方向：\(focus?.isEmpty == false ? focus! : "未指定")

        [基础档案]
        \(card.basicProfileSummary)

        [健康病史与症状记录]
        \(card.healthHistorySummary)

        [生活习惯]
        \(card.lifestyleSummary)

        [过往体检档案]
        \(card.examArchiveSummary)

        [风险评估]
        \(card.riskAssessmentSummary)

        [服务端引导分区摘要]
        \(sections.isEmpty ? "- 无" : sections)

        [聚合统计]
        - 病例：\(card.medicalCaseCount) 条
        - 症状：\(card.symptomCount) 条
        - 手术：\(card.surgeryCount) 条
        - 随访：\(card.followUpCount) 条
        - 体检报告：\(card.healthExamReportCount) 份
        - 检查检验：\(card.examinationReportCount) 份
        - 用药计划：\(card.medicationPlanCount) 条
        """

        let metadata: [String: String] = [
            "member_id": String(card.memberID),
            "member_name": card.memberName,
            "relationship": card.relationshipText,
            "gender": card.genderText,
            "age": card.ageText,
            "medical_case_count": String(card.medicalCaseCount),
            "symptom_count": String(card.symptomCount),
            "surgery_count": String(card.surgeryCount),
            "follow_up_count": String(card.followUpCount),
            "health_exam_report_count": String(card.healthExamReportCount),
            "examination_report_count": String(card.examinationReportCount),
            "medication_plan_count": String(card.medicationPlanCount),
        ]
        return AIResult(content: content, metadata: metadata)
    }

    @MainActor
    private static func makeCardPayload(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        requestedFocus: String?
    ) -> MemberProfileCard {
        let member = data.member
        let profile = data.memberMedicalProfile
        let extra = profile?.extra ?? [:]
        let ageText = member.birthDate.map(ageDescription(from:)) ?? "未提供"
        let bodyMetrics = bodyMetricsSummary(extra: extra)
        let guidanceSections = (profile?.guidanceSections ?? []).map {
            MemberProfileCard.Section(
                title: $0.title,
                summary: normalizedText($0.summary, fallback: "未提供")
            )
        }

        return MemberProfileCard(
            memberID: member.id,
            memberName: member.name,
            relationshipText: relationshipText(member.relationship),
            genderText: genderText(member.gender),
            ageText: ageText,
            bodyMetricsSummary: bodyMetrics,
            basicProfileSummary: basicProfileSummary(member: member, extra: extra, bodyMetricsSummary: bodyMetrics),
            healthHistorySummary: healthHistorySummary(profile: profile),
            lifestyleSummary: lifestyleSummary(profile: profile, extra: extra),
            examArchiveSummary: examArchiveSummary(data: data, profile: profile, extra: extra),
            riskAssessmentSummary: riskAssessmentSummary(profile: profile),
            sections: guidanceSections,
            medicalCaseCount: data.medicalCases?.count ?? 0,
            symptomCount: data.symptoms?.count ?? 0,
            surgeryCount: data.surgeries?.count ?? 0,
            followUpCount: data.followUps?.count ?? 0,
            healthExamReportCount: data.healthExamReports?.count ?? 0,
            examinationReportCount: data.examinationReports?.count ?? 0,
            medicationPlanCount: data.medicationPlans?.count ?? 0
        )
    }

    @MainActor
    private static func basicProfileSummary(
        member: SparkMedicalSyncAPI.RemoteMember,
        extra: [String: String],
        bodyMetricsSummary: String
    ) -> String {
        var parts: [String] = []
        parts.append("姓名：\(member.name)")
        parts.append("关系：\(relationshipText(member.relationship))")
        parts.append("性别：\(genderText(member.gender))")
        parts.append("年龄：\(member.birthDate.map(ageDescription(from:)) ?? "未提供")")
        parts.append("身高体重：\(bodyMetricsSummary)")
        if let occupation = text(extra["occupation"]) {
            parts.append("职业：\(occupation)")
        }
        if let sedentary = text(extra["sedentary_level"]) {
            parts.append("久坐程度：\(sedentary)")
        }
        if member.bloodType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            parts.append("血型：\(member.bloodType)")
        }
        return parts.joined(separator: "；")
    }

    @MainActor
    private static func healthHistorySummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
    ) -> String {
        var parts: [String] = []
        parts.append("慢病：\(joined(profile?.chronicConditions, fallback: "无明确记录"))")
        parts.append("过敏：\(joined(profile?.allergies, fallback: "无明确记录"))")
        parts.append("家族史：\(familyHistoryText(profile?.familyHistory ?? []))")
        parts.append("症状随访：\(joined(profile?.symptomFollowUpFocus, fallback: "无明确记录"))")
        let medications = profile?.medicationFocus.map { "\($0.drugName)（\($0.summary)）" } ?? []
        parts.append("用药关注：\(joined(medications, fallback: "无明确记录"))")
        let surgeries = profile?.surgeryFocus.map { "\($0.procedureName)（\($0.summary)）" } ?? []
        parts.append("手术史：\(joined(surgeries, fallback: "无明确记录"))")
        return parts.joined(separator: "；")
    }

    @MainActor
    private static func lifestyleSummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        extra: [String: String]
    ) -> String {
        var parts: [String] = []
        if let smoking = profile?.smokingProfile {
            parts.append("吸烟：\(smokingText(smoking))")
        }
        if let drinking = profile?.drinkingProfile {
            parts.append("饮酒：\(drinkingText(drinking))")
        }
        if let exercise = profile?.exerciseProfile {
            parts.append("运动：\(exerciseText(exercise))")
        }
        if let sleepHours = profile?.sleepHours {
            parts.append("睡眠时长：\(String(format: "%.1f", sleepHours)) 小时/天")
        }
        if let sleepQuality = text(extra["sleep_quality"]) {
            parts.append("睡眠质量：\(sleepQuality)")
        }
        return parts.isEmpty ? "未提供明确的生活习惯资料。" : parts.joined(separator: "；")
    }

    @MainActor
    private static func examArchiveSummary(
        data: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        extra: [String: String]
    ) -> String {
        var parts: [String] = []
        if let year = text(extra["last_exam_year"]) {
            parts.append("最近体检时间：\(year)")
        }
        if let institution = text(extra["exam_institution"]) {
            parts.append("体检机构：\(institution)")
        }
        if let reportSummary = text(extra["exam_report_summary"]) {
            parts.append("报告摘要：\(reportSummary)")
        }
        if let planSummary = text(profile?.examPlanSummary) {
            parts.append("计划摘要：\(planSummary)")
        }
        parts.append("体检报告数：\(data.healthExamReports?.count ?? 0) 份")
        return parts.joined(separator: "；")
    }

    @MainActor
    private static func riskAssessmentSummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
    ) -> String {
        text(profile?.riskAssessmentSummary)
            ?? text(profile?.notes)
            ?? "暂无明确的风险评估摘要。"
    }

    private nonisolated static func bodyMetricsSummary(extra: [String: String]) -> String {
        let height = text(extra["height_cm"])
        let weight = text(extra["weight_kg"])
        switch (height, weight) {
        case let (h?, w?):
            return "\(h) cm / \(w) kg"
        case let (h?, nil):
            return "\(h) cm"
        case let (nil, w?):
            return "\(w) kg"
        default:
            return "未提供"
        }
    }

    @MainActor
    private static func familyHistoryText(_ records: [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord]) -> String {
        let mapped = records.map { record in
            let disease = normalizedText(record.disease, fallback: "未命名疾病")
            let relative = normalizedText(record.relative, fallback: "家属")
            return "\(relative)：\(disease)"
        }
        return joined(mapped, fallback: "无明确记录")
    }

    @MainActor
    private static func smokingText(_ value: SparkMedicalSyncAPI.RemoteSmokingProfile) -> String {
        let parts = [text(value.status), text(value.count), text(value.historyDuration), text(value.quitDuration)].compactMap { $0 }
        return parts.isEmpty ? "未提供" : parts.joined(separator: " / ")
    }

    @MainActor
    private static func drinkingText(_ value: SparkMedicalSyncAPI.RemoteDrinkingProfile) -> String {
        var parts = [text(value.status), text(value.count), text(value.historyDuration), text(value.quitDuration)].compactMap { $0 }
        if value.types.isEmpty == false {
            parts.append(value.types.joined(separator: "、"))
        }
        return parts.isEmpty ? "未提供" : parts.joined(separator: " / ")
    }

    @MainActor
    private static func exerciseText(_ value: SparkMedicalSyncAPI.RemoteExerciseProfile) -> String {
        var parts = [text(value.frequency), text(value.intensity), text(value.durationMinutes)].compactMap { $0 }
        if value.types.isEmpty == false {
            parts.append(value.types.joined(separator: "、"))
        }
        return parts.isEmpty ? "未提供" : parts.joined(separator: " / ")
    }

    private nonisolated static func joined(_ values: [String]?, fallback: String) -> String {
        let filtered = (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return filtered.isEmpty ? fallback : filtered.joined(separator: "、")
    }

    private nonisolated static func relationshipText(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "self", "本人":
            return "本人"
        case "mother":
            return "母亲"
        case "father":
            return "父亲"
        case "wife":
            return "妻子"
        case "husband":
            return "丈夫"
        case "daughter":
            return "女儿"
        case "son":
            return "儿子"
        case let raw? where raw.isEmpty == false:
            return raw
        default:
            return "未提供"
        }
    }

    private nonisolated static func genderText(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "male":
            return "男"
        case "female":
            return "女"
        default:
            return "未提供"
        }
    }

    private nonisolated static func ageDescription(from birthDate: Date) -> String {
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return years > 0 ? "\(years)岁" : "未提供"
    }

    private nonisolated static func text(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func normalizedText(_ value: String?, fallback: String) -> String {
        text(value) ?? fallback
    }
}

private struct MemberProfileCard {
    struct Section {
        let title: String
        let summary: String
    }

    let memberID: Int
    let memberName: String
    let relationshipText: String
    let genderText: String
    let ageText: String
    let bodyMetricsSummary: String
    let basicProfileSummary: String
    let healthHistorySummary: String
    let lifestyleSummary: String
    let examArchiveSummary: String
    let riskAssessmentSummary: String
    let sections: [Section]
    let medicalCaseCount: Int
    let symptomCount: Int
    let surgeryCount: Int
    let followUpCount: Int
    let healthExamReportCount: Int
    let examinationReportCount: Int
    let medicationPlanCount: Int
}