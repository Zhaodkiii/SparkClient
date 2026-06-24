import Foundation

/// 医疗模块各小节进度数据构建器
/// 作用：根据后端完整医疗档案快照、本地缓存填写进度，生成页面展示的小节进度列表；
/// 优先使用后端指导摘要/状态，无指导数据则自动拼接档案内容生成摘要、判断填写完成状态；
/// 本地缓存进度优先级高于自动推断，用于保留用户手动填写的自定义摘要与完成标记。
enum MemberMedicalModuleSectionBuilder {
    /// 批量构建医疗模块全部小节进度模型数组
    /// - Parameters:
    ///   - completeData: 服务端返回成员完整医疗档案快照（基础信息、病史、生活习惯、体检报告等全量数据）
    ///   - storedProgress: 本地持久化的各小节填写进度缓存，key为小节code，value为进度记录
    /// - Returns: 医疗所有小节UI进度展示数组
    static func buildSections(
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        storedProgress: [String: MemberModuleSectionProgressRecord]
    ) -> [MemberModuleSectionProgress] {
        // 将后端分节指导数据转为code映射字典，方便快速读取
        let guidanceMap = guidanceSectionMap(from: completeData.memberMedicalProfile)

        // 遍历所有医疗小节枚举，逐个生成进度对象
        return MemberMedicalSectionCode.allCases.map { code in
            // 自动根据档案数据生成小节默认摘要
            let inferredSummary = summary(for: code, completeData: completeData, guidanceMap: guidanceMap)
            // 自动根据档案内容判断小节默认完成状态
            let inferredStatus = status(for: code, completeData: completeData, guidanceMap: guidanceMap, summary: inferredSummary)

            // 如果本地存在该小节缓存进度，优先复用缓存内容
            if let stored = storedProgress[code.rawValue] {
                return MemberModuleSectionProgress(
                    module: .medical,
                    sectionCode: code.rawValue,
                    title: code.title,
                    subtitle: code.subtitle,
                    iconName: code.iconName,
                    // 缓存有自定义摘要则用缓存，否则使用自动推断摘要
                    summary: stored.summary.isEmpty ? inferredSummary : stored.summary,
                    // 缓存标记为已完成则强制使用完成状态，其余情况使用自动推断状态
                    status: stored.status == .completed ? .completed : inferredStatus
                )
            }

            // 无本地缓存，直接使用后端数据自动推断的摘要与状态
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

    /// 将后端档案内分节指导数组转为 [小节code: 小节指导摘要] 映射字典，便于快速查找
    private static func guidanceSectionMap(
        from profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
    ) -> [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary] {
        guard let sections = profile?.guidanceSections else { return [:] }
        return Dictionary(uniqueKeysWithValues: sections.map { ($0.sectionCode, $0) })
    }

    /// 获取指定小节展示摘要文本
    /// 优先级：后端指导摘要 > 自动拼接档案生成摘要
    private static func summary(
        for code: MemberMedicalSectionCode,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        guidanceMap: [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary]
    ) -> String {
        // 存在后端指导摘要且非空，直接使用
        if let guidance = guidanceMap[code.rawValue], guidance.summary.isEmpty == false {
            return guidance.summary
        }

        let profile = completeData.memberMedicalProfile
        let member = completeData.member
        let extra = profile?.extra ?? [:]

        // 根据小节分类，拼接对应档案内容生成摘要
        switch code {
        case .basicProfile:
            return basicProfileSummary(member: member, extra: extra)
        case .healthHistory:
            return healthHistorySummary(profile: profile, completeData: completeData)
        case .lifestyle:
            return lifestyleSummary(profile: profile)
        case .examArchive:
            // 优先展示体检计划，拼接基础体检摘要
            if let examPlan = profile?.examPlanSummary, examPlan.isEmpty == false {
                let base = examArchiveSummary(profile: profile, completeData: completeData)
                return base.isEmpty ? examPlan : "\(base) · \(examPlan)"
            }
            return examArchiveSummary(profile: profile, completeData: completeData)
        }
    }

    /// 判断小节填写状态（未开始/填写中/已完成）
    /// 优先级：后端指导状态 > 自动读取档案内容判断
    private static func status(
        for code: MemberMedicalSectionCode,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData,
        guidanceMap: [String: SparkMedicalSyncAPI.RemoteMemberMedicalProfileSectionSummary],
        summary: String
    ) -> MemberModuleSectionStatus {
        // 后端返回分节指导状态，直接映射转换
        if let guidance = guidanceMap[code.rawValue] {
            return mapGuidanceStatus(guidance.status)
        }

        let profile = completeData.memberMedicalProfile
        let extra = profile?.extra ?? [:]

        // 无后端指导，读取档案数据自动判断完成度
        switch code {
        case .basicProfile:
            // 判断基础档案必填项是否齐全：性别、生日、身高、体重、久坐等级
            let hasGender = completeData.member.gender != "unknown"
            let hasBirthDate = completeData.member.birthDate != nil
            let hasHeight = Double(extra["height_cm"] ?? "") ?? 0 > 0
            let hasWeight = Double(extra["weight_kg"] ?? "") ?? 0 > 0
            let hasSedentary = (extra["sedentary_hours_level"] ?? extra["sedentary_level"])?.isEmpty == false
            // 全部齐全=已完成
            if hasGender && hasBirthDate && hasHeight && hasWeight && hasSedentary {
                return .completed
            }
            // 至少填了一项=填写中
            if hasGender || hasBirthDate != nil || hasHeight || hasWeight {
                return .incomplete
            }
            // 无任何内容=未开始
            return .notStarted
        case .healthHistory:
            // 存在病史相关内容
            if hasHealthHistoryContent(profile: profile, completeData: completeData) {
                // 随访状态未知则标记未完善，否则视为完成
                return extra["symptom_follow_up_status"] == "unknown" ? .incomplete : .completed
            }
            return .notStarted
        case .lifestyle:
            // 摘要为待填写=未开始，否则已完成
            return lifestyleSummary(profile: profile) == L10n.text("member.setup.common.pending") ? .notStarted : .completed
        case .examArchive:
            // 存在体检报告/体检计划视为已完成
            if examArchiveSummary(profile: profile, completeData: completeData).isEmpty == false
                || profile?.examPlanSummary?.isEmpty == false {
                return .completed
            }
            return .notStarted
        }
    }

    /// 将后端原始状态字符串映射为前端枚举状态
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

    /// 拼接基础档案小节摘要：性别、年龄、身高、体重、职业
    private static func basicProfileSummary(member: SparkMedicalSyncAPI.RemoteMember, extra: [String: String]) -> String {
        var pieces: [String] = []
        switch member.gender {
        case "male": pieces.append("男")
        case "female": pieces.append("女")
        default: break
        }
        // 计算年龄并拼接
        if let birthDate = member.birthDate {
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
            if age > 0 { pieces.append("\(age)岁") }
        }
        // 身高
        if let height = Double(extra["height_cm"] ?? ""), height > 0 {
            pieces.append(String(format: "%.0fcm", height))
        }
        // 体重
        if let weight = Double(extra["weight_kg"] ?? ""), weight > 0 {
            pieces.append(String(format: "%.0fkg", weight))
        }
        // 职业
        if let occupation = extra["occupation"], occupation.isEmpty == false {
            pieces.append(occupation)
        }
        // 无内容返回待填写占位文案
        return pieces.isEmpty ? L10n.text("member.setup.common.pending") : pieces.joined(separator: " · ")
    }

    /// 拼接病史小节摘要：随访症状、慢性病、长期用药、手术史、过敏、线下症状、用药计划、手术记录
    private static func healthHistorySummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> String {
        var pieces: [String] = []
        if let profile {
            // 随访关注症状
            if profile.symptomFollowUpFocus.isEmpty == false {
                pieces.append(profile.symptomFollowUpFocus.joined(separator: " · "))
            }
            // 慢性病列表
            if profile.chronicConditions.isEmpty == false {
                pieces.append(profile.chronicConditions.joined(separator: "、"))
            }
            // 长期用药摘要
            let medicationSummary = MedicationFormSupport.profileSummary(from: profile.medicationFocus)
            if medicationSummary != "暂无长期用药" {
                pieces.append(medicationSummary)
            }
            // 手术史
            if profile.surgeryFocus.isEmpty == false {
                pieces.append(profile.surgeryFocus.map(\.procedureName).joined(separator: " · "))
            }
            // 过敏史
            if profile.allergies.isEmpty == false {
                pieces.append(profile.allergies.joined(separator: "、"))
            }
        }
        // 线下录入症状记录
        if pieces.isEmpty, let symptoms = completeData.symptoms, symptoms.isEmpty == false {
            pieces.append(symptoms.map { SymptomFormSupport.summaryLine(for: $0) }.joined(separator: " · "))
        }
        // 有效用药计划
        if pieces.isEmpty, let plans = completeData.medicationPlans {
            let active = plans.filter { $0.status == "active" || $0.status == "paused" }
            if active.isEmpty == false {
                pieces.append(active.map { MedicationFormSupport.summaryLine(for: $0) }.joined(separator: " / "))
            }
        }
        // 线下手术记录
        if pieces.isEmpty, let surgeries = completeData.surgeries, surgeries.isEmpty == false {
            pieces.append(surgeries.map(\.procedureName).joined(separator: " · "))
        }
        return pieces.isEmpty ? L10n.text("member.setup.common.pending") : pieces.joined(separator: " · ")
    }

    /// 判断病史小节是否存在有效填写内容
    private static func hasHealthHistoryContent(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> Bool {
        // 摘要非占位文案，代表有内容
        if healthHistorySummary(profile: profile, completeData: completeData) != L10n.text("member.setup.common.pending") {
            return true
        }
        let extra = profile?.extra ?? [:]
        // 任意一项病史状态标记存在，视为有内容
        return ["chronic_condition_status", "long_term_medication_status", "surgery_status", "allergy_status", "family_history_screening_status", "symptom_follow_up_status"]
            .contains { extra[$0]?.isEmpty == false }
    }

    /// 拼接生活习惯小节摘要：吸烟、饮酒、运动、睡眠时长
    private static func lifestyleSummary(profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?) -> String {
        guard let profile else { return L10n.text("member.setup.common.pending");}
        var pieces: [String] = []
        // 吸烟（非从不吸烟）
        let smokingStatus = profile.smokingProfile?.status ?? ""
        if smokingStatus.isEmpty == false,
           smokingStatus != "never" {
            pieces.append("吸烟")
        }
        // 饮酒（非不饮酒）
        let drinkingStatus = profile.drinkingProfile?.status ?? ""
        if drinkingStatus.isEmpty == false,
           drinkingStatus != "none" {
            pieces.append("饮酒")
        }
        // 运动（非无运动）
        let exerciseFrequency = profile.exerciseProfile?.frequency ?? ""
        if exerciseFrequency.isEmpty == false,
           exerciseFrequency != "none" {
            pieces.append("运动")
        }
        // 睡眠时长
        if let sleepHours = profile.sleepHours {
            pieces.append(String(format: "%.0f小时睡眠", sleepHours))
        }
        return pieces.isEmpty ? L10n.text("member.setup.common.pending") : pieces.joined(separator: " · ")
    }

    /// 拼接体检档案小节摘要：有无体检史、上次体检年份、体检报告、检验报告
    private static func examArchiveSummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) -> String {
        var pieces: [String] = []
        let extra = profile?.extra ?? [:]
        // 标记存在体检史
        if extra["has_exam_history"] == "true" || extra["has_exam_history"] == "1" {
            pieces.append("有体检史")
        }
        // 上次体检年份
        if let year = extra["last_exam_year"], year.isEmpty == false {
            pieces.append(year)
        }
        // 体检报告第一条年份
        if let reports = completeData.healthExamReports, let first = reports.first, let examDate = first.examDate {
            pieces.append("\(Calendar.current.component(.year, from: examDate))年体检")
        }
        // 存在检验报告单
        if completeData.examinationReports?.isEmpty == false {
            pieces.append("有检查报告")
        }
        return pieces.joined(separator: " · ")
    }
}
