import Foundation

/// 家庭成员健康模块业务用例
/// Sendable：线程安全，可在多异步Task中安全传递
/// 职责：封装成员医疗档案、功能模块配置的增改查统一业务逻辑，统一接口请求与日志埋点
struct MemberModuleSetupUseCase: Sendable {
    /// 医疗相关接口查询客户端
    let medicalQueryAPI: SparkMedicalQueryAPI
    /// 全局日志输出器
    let logger: Logger

    /// 日志模块标识，统一归类医疗相关日志
    private let logModule = LogModule.medical

    /// 保存/更新成员医疗基础档案
    /// 存在档案则执行更新，无档案则新建
    /// - Parameters:
    ///   - memberID: 家庭成员ID
    ///   - chronicConditions: 慢性病列表
    ///   - allergies: 过敏源列表
    ///   - allergyDetails: 过敏明细
    ///   - allergyHistory: 过敏史补充说明
    ///   - familyHistory: 家族病史记录
    ///   - smokingProfile: 吸烟档案
    ///   - drinkingProfile: 饮酒档案
    ///   - exerciseProfile: 运动档案
    ///   - sleepHours: 平均睡眠时长（小时）
    ///   - examFocus: 重点体检项目
    ///   - symptomFollowUpFocus: 需要持续随访的症状
    ///   - notes: 其他综合备注
    ///   - extra: 扩展自定义字段
    /// - Returns: 服务端返回完整医疗档案实体
    /// - Throws: 网络请求、接口校验异常
    func saveMedicalProfile(
        memberID: Int,
        chronicConditions: [String],
        allergies: [String],
        allergyDetails: [String: SparkMedicalSyncAPI.RemoteAllergyDetail],
        allergyHistory: String,
        familyHistory: [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord],
        smokingProfile: SparkMedicalSyncAPI.RemoteSmokingProfile,
        drinkingProfile: SparkMedicalSyncAPI.RemoteDrinkingProfile,
        exerciseProfile: SparkMedicalSyncAPI.RemoteExerciseProfile,
        sleepHours: Double?,
        examFocus: [String],
        symptomFollowUpFocus: [String],
        notes: String,
        extra: [String: String] = [:]
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalProfile {
        // 记录方法执行起始时间，用于统计耗时
        let startedAt = Date()
        // 组装接口提交载荷
        let payload = SparkMedicalWorkflowAPI.MemberMedicalProfileSavePayload(
            member: memberID,
            chronicConditions: chronicConditions,
            allergies: allergies,
            allergyDetails: allergyDetails,
            allergyHistory: allergyHistory,
            familyHistory: familyHistory,
            smokingProfile: smokingProfile,
            drinkingProfile: drinkingProfile,
            exerciseProfile: exerciseProfile,
            sleepHours: sleepHours,
            examFocus: examFocus,
            symptomFollowUpFocus: symptomFollowUpFocus,
            notes: notes,
            extra: extra
        )
        // 查询当前成员是否已有医疗档案
        let existing = try await medicalQueryAPI.listMemberMedicalProfiles(memberID: memberID).first
        let saved: SparkMedicalSyncAPI.RemoteMemberMedicalProfile
        if let existing {
            // 已有档案：执行更新接口
            saved = try await medicalQueryAPI.updateMemberMedicalProfile(id: existing.id, payload: payload)
        } else {
            // 无档案：执行新建接口
            saved = try await medicalQueryAPI.createMemberMedicalProfile(payload)
        }
        // 计算接口耗时并格式化保留3位小数
        let cost = String(format: "%.3f", Date().timeIntervalSince(startedAt))
        // 打印成功日志，携带成员ID、档案ID、耗时用于问题排查
        logger.info(
            "成员医疗档案保存成功 memberID=\(memberID) profileID=\(saved.id) cost=\(cost)s",
            module: logModule
        )
        return saved
    }

    /// 保存/更新单个健康功能模块配置
    /// 同一模块存在配置则更新，不存在则创建
    /// - Parameters:
    ///   - memberID: 家庭成员ID
    ///   - moduleCode: 功能模块唯一编码（Medical/Nutrition等）
    ///   - isEnabled: 模块是否启用勾选
    ///   - isCompleted: 模块资料是否填写完成
    ///   - displayOrder: 前端展示排序序号
    ///   - summaryText: 模块状态简短摘要文案
    ///   - detailData: 模块扩展详情结构化数据
    ///   - completedAt: 模块完成填写时间，未完成传nil
    ///   - extra: 额外扩展字段
    /// - Returns: 服务端返回模块配置完整实体
    /// - Throws: 网络、接口校验异常
    func saveModuleSetting(
        memberID: Int,
        moduleCode: String,
        isEnabled: Bool,
        isCompleted: Bool,
        displayOrder: Int,
        summaryText: String,
        detailData: [String: String] = [:],
        completedAt: Date? = nil,
        extra: [String: String] = [:]
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberModuleSetting {
        let startedAt = Date()
        // 组装模块配置提交载荷
        let payload = SparkMedicalWorkflowAPI.MemberModuleSettingSavePayload(
            member: memberID,
            moduleCode: moduleCode,
            isEnabled: isEnabled,
            isCompleted: isCompleted,
            displayOrder: displayOrder,
            summaryText: summaryText,
            detailData: detailData,
            completedAt: completedAt,
            extra: extra
        )
        // 查询该成员下当前模块是否已存在配置
        let existing = try await medicalQueryAPI.listMemberModuleSettings(memberID: memberID, moduleCode: moduleCode).first
        let saved: SparkMedicalSyncAPI.RemoteMemberModuleSetting
        if let existing {
            saved = try await medicalQueryAPI.updateMemberModuleSetting(id: existing.id, payload: payload)
        } else {
            saved = try await medicalQueryAPI.createMemberModuleSetting(payload)
        }
        let cost = String(format: "%.3f", Date().timeIntervalSince(startedAt))
        logger.info(
            "成员模块配置保存成功 memberID=\(memberID) moduleCode=\(moduleCode) settingID=\(saved.id) cost=\(cost)s",
            module: logModule
        )
        return saved
    }

    /// 加载指定成员全部健康功能模块配置
    /// - Parameter memberID: 家庭成员ID
    /// - Returns: 当前成员所有模块配置列表
    /// - Throws: 网络请求异常
    func loadModuleSettings(
        memberID: Int
    ) async throws -> [SparkMedicalSyncAPI.RemoteMemberModuleSetting] {
        let startedAt = Date()
        // 请求接口拉取全部模块配置
        let result = try await medicalQueryAPI.listMemberModuleSettings(memberID: memberID)
        let cost = String(format: "%.3f", Date().timeIntervalSince(startedAt))
        logger.info(
            "成员模块配置加载成功 memberID=\(memberID) count=\(result.count) cost=\(cost)s",
            module: logModule
        )
        return result
    }

    /// 保存单个分组进度到模块配置的 `extra.section_progress`。
    func saveSectionProgress(
        memberID: Int,
        module: MemberSetupModule,
        sectionCode: String,
        status: MemberModuleSectionStatus,
        summary: String
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberModuleSetting {
        let existing = try await medicalQueryAPI.listMemberModuleSettings(memberID: memberID, moduleCode: module.rawValue).first
        var progressMap = MemberModuleSectionProgressCodec.decode(from: existing?.extra)
        progressMap[sectionCode] = MemberModuleSectionProgressRecord(
            sectionCode: sectionCode,
            summary: summary,
            status: status
        )

        let isModuleCompleted = isModuleCompleted(module: module, progressMap: progressMap)
        let mergedExtra = mergeSectionProgress(into: existing?.extra, progressMap: progressMap)

        return try await saveModuleSetting(
            memberID: memberID,
            moduleCode: module.rawValue,
            isEnabled: true,
            isCompleted: isModuleCompleted,
            displayOrder: module.displayOrder,
            summaryText: summary.isEmpty ? (existing?.summaryText ?? module.title) : summary,
            detailData: existing?.detailData ?? [:],
            completedAt: isModuleCompleted ? (existing?.completedAt ?? Date()) : nil,
            extra: mergedExtra
        )
    }

    /// 标记模块已选中但未完成（暂不填写场景）。
    func markModuleSelected(
        memberID: Int,
        module: MemberSetupModule
    ) async throws -> SparkMedicalSyncAPI.RemoteMemberModuleSetting {
        let existing = try await medicalQueryAPI.listMemberModuleSettings(memberID: memberID, moduleCode: module.rawValue).first
        return try await saveModuleSetting(
            memberID: memberID,
            moduleCode: module.rawValue,
            isEnabled: true,
            isCompleted: existing?.isCompleted ?? false,
            displayOrder: module.displayOrder,
            summaryText: existing?.summaryText ?? "",
            detailData: existing?.detailData ?? [:],
            completedAt: existing?.completedAt,
            extra: existing?.extra ?? [:]
        )
    }

    func sectionProgressMap(
        memberID: Int,
        module: MemberSetupModule
    ) async throws -> [String: MemberModuleSectionProgressRecord] {
        let existing = try await medicalQueryAPI.listMemberModuleSettings(memberID: memberID, moduleCode: module.rawValue).first
        return MemberModuleSectionProgressCodec.decode(from: existing?.extra)
    }

    private func mergeSectionProgress(
        into extra: [String: String]?,
        progressMap: [String: MemberModuleSectionProgressRecord]
    ) -> [String: String] {
        var merged = extra ?? [:]
        merged[MemberModuleSectionProgressCodec.extraKey] = MemberModuleSectionProgressCodec.encode(progressMap)
        return merged
    }

    private func isModuleCompleted(
        module: MemberSetupModule,
        progressMap: [String: MemberModuleSectionProgressRecord]
    ) -> Bool {
        switch module {
        case .medical, .nutrition, .dailyHealth:
            return progressMap.values.contains { $0.status == .completed }
        }
    }
}
