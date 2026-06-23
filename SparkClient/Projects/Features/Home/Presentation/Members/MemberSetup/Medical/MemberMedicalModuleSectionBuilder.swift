import Foundation

enum MemberMedicalModuleSectionBuilder {
    static func buildSections(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        storedProgress: [String: MemberModuleSectionProgressRecord]
    ) -> [MemberModuleSectionProgress] {
        let guidanceMap = guidanceSectionMap(from: completeData.memberMedicalProfile)

        return MemberMedicalSectionCode.allCases.map { code in
            let inferredSummary = summary(for: code, completeData: completeData, guidanceMap: guidanceMap)
            let inferredStatus = status(for: code, completeData: completeData, guidanceMap: guidanceMap, summary: inferredSummary)

            if let stored = storedProgress[code.rawValue] {
                return MemberModuleSectionProgress(
                    module: .medical,
                    sectionCode: code.rawValue,
                    title: code.title,
                    subtitle: code.subtitle,
                    iconName: code.iconName,
                    summary: stored.summary.isEmpty ? inferredSummary : stored.summary,
                    status: stored.status == .completed ? .completed : inferredStatus
                )
            }

            return MemberModuleSectionProgress(
                module: .medical,
                sectionCode: code.rawValue,
                title: code.title,
                subtitle: code.subtitle,
                iconName: code.iconName,
                summary: inferredSummary,
                status: inferredStatus
            )
        }
    }

    private static func guidanceSectionMap(
        from profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
    ) -> [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary] {
        guard let sections = profile?.guidanceSections else { return [:] }
        return Dictionary(uniqueKeysWithValues: sections.map { ($0.sectionCode, $0) })
    }

    private static func summary(
        for code: MemberMedicalSectionCode,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        guidanceMap: [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary]
    ) -> String {
        if let guidance = guidanceMap[code.rawValue], guidance.summary.isEmpty == false {
            return guidance.summary
        }

        let profile = completeData.memberMedicalProfile
        let member = completeData.member
        let extra = profile?.extra ?? [:]

        switch code {
        case .basicProfile:
            return basicProfileSummary(member: member, extra: extra)
        case .healthHistory:
            return healthHistorySummary(profile: profile, completeData: completeData)
        case .lifestyle:
            return lifestyleSummary(profile: profile)
        case .examArchive:
            if let examPlan = profile?.examPlanSummary, examPlan.isEmpty == false {
                let base = examArchiveSummary(profile: profile, completeData: completeData)
                return base.isEmpty ? examPlan : "\(base) · \(examPlan)"
            }
            return examArchiveSummary(profile: profile, completeData: completeData)
        }
    }

    private static func status(
        for code: MemberMedicalSectionCode,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        guidanceMap: [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary],
        summary: String
    ) -> MemberModuleSectionStatus {
        if let guidance = guidanceMap[code.rawValue] {
            return mapGuidanceStatus(guidance.status)
        }

        let profile = completeData.memberMedicalProfile
        let extra = profile?.extra ?? [:]

        switch code {
        case .basicProfile:
            let hasGender = completeData.member.gender != "unknown"
            let hasBirthDate = completeData.member.birthDate != nil
            let hasHeight = Double(extra["height_cm"] ?? "") ?? 0 > 0
            let hasWeight = Double(extra["weight_kg"] ?? "") ?? 0 > 0
            let hasSedentary = (extra["sedentary_hours_level"] ?? extra["sedentary_level"])?.isEmpty == false
            if hasGender && hasBirthDate && hasHeight && hasWeight && hasSedentary {
                return .completed
            }
            if hasGender || hasBirthDate != nil || hasHeight || hasWeight {
                return .incomplete
            }
            return .notStarted
        case .healthHistory:
            if hasHealthHistoryContent(profile: profile, completeData: completeData) {
                return extra["symptom_follow_up_status"] == "unknown" ? .incomplete : .completed
            }
            return .notStarted
        case .lifestyle:
            return lifestyleSummary(profile: profile) == "待补充" ? .notStarted : .completed
        case .examArchive:
            if examArchiveSummary(profile: profile, completeData: completeData).isEmpty == false
                || profile?.examPlanSummary?.isEmpty == false {
                return .completed
            }
            return .notStarted
        }
    }

    private static func mapGuidanceStatus(_ raw: String) -> MemberModuleSectionStatus {
        switch raw {
        case "completed":
            return .completed
        case "in_progress", "incomplete":
            return .incomplete
        default:
            return .notStarted
        }
    }

    private static func basicProfileSummary(member: SparkMedicalSyncAPI.RemoteMember, extra: [String: String]) -> String {
        var pieces: [String] = []
        switch member.gender {
        case "male": pieces.append("男")
        case "female": pieces.append("女")
        default: break
        }
        if let birthDate = member.birthDate {
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            if age > 0 { pieces.append("\(age)岁") }
        }
        if let height = Double(extra["height_cm"] ?? ""), height > 0 {
            pieces.append(String(format: "%.0fcm", height))
        }
        if let weight = Double(extra["weight_kg"] ?? ""), weight > 0 {
            pieces.append(String(format: "%.0fkg", weight))
        }
        if let occupation = extra["occupation"], occupation.isEmpty == false {
            pieces.append(occupation)
        }
        return pieces.isEmpty ? "待补充" : pieces.joined(separator: " · ")
    }

    private static func healthHistorySummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> String {
        var pieces: [String] = []
        if let profile {
            if profile.symptomFollowUpFocus.isEmpty == false {
                pieces.append(profile.symptomFollowUpFocus.joined(separator: " · "))
            }
            if profile.chronicConditions.isEmpty == false {
                pieces.append(profile.chronicConditions.joined(separator: "、"))
            }
            let medicationSummary = MedicationFormSupport.profileSummary(from: profile.medicationFocus)
            if medicationSummary != "暂无长期用药" {
                pieces.append(medicationSummary)
            }
            if profile.surgeryFocus.isEmpty == false {
                pieces.append(profile.surgeryFocus.map(\.procedureName).joined(separator: " · "))
            }
            if profile.allergies.isEmpty == false {
                pieces.append(profile.allergies.joined(separator: "、"))
            }
        }
        if pieces.isEmpty, let symptoms = completeData.symptoms, symptoms.isEmpty == false {
            pieces.append(symptoms.map { SymptomFormSupport.summaryLine(for: $0) }.joined(separator: " · "))
        }
        if pieces.isEmpty, let plans = completeData.medicationPlans {
            let active = plans.filter { $0.status == "active" || $0.status == "paused" }
            if active.isEmpty == false {
                pieces.append(active.map { MedicationFormSupport.summaryLine(for: $0) }.joined(separator: " / "))
            }
        }
        if pieces.isEmpty, let surgeries = completeData.surgeries, surgeries.isEmpty == false {
            pieces.append(surgeries.map(\.procedureName).joined(separator: " · "))
        }
        return pieces.isEmpty ? "待补充" : pieces.joined(separator: " · ")
    }

    private static func hasHealthHistoryContent(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> Bool {
        if healthHistorySummary(profile: profile, completeData: completeData) != "待补充" {
            return true
        }
        let extra = profile?.extra ?? [:]
        return ["chronic_condition_status", "long_term_medication_status", "surgery_status", "allergy_status", "family_history_screening_status", "symptom_follow_up_status"]
            .contains { extra[$0]?.isEmpty == false }
    }

    private static func lifestyleSummary(profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?) -> String {
        guard let profile else { return "待补充" }
        var pieces: [String] = []
        if profile.smokingProfile.status.isEmpty == false,
           profile.smokingProfile.status != "never" {
            pieces.append("吸烟")
        }
        if profile.drinkingProfile.status.isEmpty == false,
           profile.drinkingProfile.status != "none" {
            pieces.append("饮酒")
        }
        if profile.exerciseProfile.frequency.isEmpty == false,
           profile.exerciseProfile.frequency != "none" {
            pieces.append("运动")
        }
        if let sleepHours = profile.sleepHours {
            pieces.append(String(format: "%.0f小时睡眠", sleepHours))
        }
        return pieces.isEmpty ? "待补充" : pieces.joined(separator: " · ")
    }

    private static func examArchiveSummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> String {
        var pieces: [String] = []
        let extra = profile?.extra ?? [:]
        if extra["has_exam_history"] == "true" || extra["has_exam_history"] == "1" {
            pieces.append("有体检史")
        }
        if let year = extra["last_exam_year"], year.isEmpty == false {
            pieces.append(year)
        }
        if let reports = completeData.healthExamReports, let first = reports.first, let examDate = first.examDate {
            pieces.append("\(Calendar.current.component(.year, from: examDate))年体检")
        }
        if completeData.examinationReports?.isEmpty == false {
            pieces.append("有检查报告")
        }
        return pieces.joined(separator: " · ")
    }
}
