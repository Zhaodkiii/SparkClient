import Foundation

/// 医疗模块引导流程的路由枚举。
/// `MemberMedicalSetupSheetView.path` 按顺序压栈，每个 case 对应一个独立页面。
enum MedicalGuideRoute: Hashable {
    // MARK: - 基础档案

    case intro          // 基础档案介绍页
    case gender         // 性别
    case birthDate      // 出生日期
    case height         // 身高
    case weight         // 体重
    case occupation     // 职业
    case sedentary      // 久坐时间
    case basicSummary   // 基础档案汇总

    // MARK: - 健康病史与症状记录

    case history              // 病史模块介绍页
    case chronicConditions    // 既往疾病 / 慢病
    case longTermMedication   // 长期用药
    case surgeryHistory       // 手术史
    case allergyHistory       // 过敏史
    case historySummary       // 病史填写汇总（不含家族史）
    case familyHistory        // 家族病史
    case symptomFollowUp      // 症状观察 / 随访（辅助入口，非主流程必经）

    // MARK: - 生活习惯

    case lifestyle        // 生活习惯介绍页
    case smoking          // 吸烟
    case drinking         // 饮酒
    case exercise         // 运动
    case sleep            // 睡眠
    case lifestyleSummary // 生活习惯汇总

    // MARK: - 过往体检档案（AI 体检计划闭环）

    case examArchiveIntro            // 体检档案介绍页
    case examArchive                 // 报告导入 / 是否有历史报告表单
    case examArchiveReportPicker     // 汇总回跳：选择或上传报告（复用表单页）
    case examArchiveAIExtractConfirm // Path A：AI 异常项确认（5.3）
    case examArchiveFollowUpPlan     // Path A：近期随访建议（5.4）
    case examArchivePlanGenerating   // 计划生成中（5.5）
    case examArchivePlanResult       // AI 定制体检单结果（5.6）
    case examArchiveBaselineIntro    // Path B：无历史报告说明（5.7）
    case examArchiveEvidenceConfirm  // Path B：生成依据确认（5.8）
    case examArchiveSummary          // 体检档案模块汇总（5.9）
    case keyIndicators               // 关键指标补充（可选，非主路径必经）
    case keyIndicatorSummary         // 关键指标补充汇总

    // MARK: - 全流程收尾

    case summary // 医疗模块总汇总 / 保存页
}
