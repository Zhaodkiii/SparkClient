import Foundation

extension ToolHub {
    func runQueryMemberProfile(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let queryType = (invocation.arguments["query_type"] ?? "summary").trimmingCharacters(in: .whitespacesAndNewlines)
        let targetMemberID: Int? = {
            if let value = invocation.arguments["member_id"], let id = Int(value) {
                return id
            }
            if let value = invocation.arguments["patient_id"], let id = Int(value) {
                return id
            }
            return context.memberID
        }()

        let memberID: Int
        if let targetMemberID {
            memberID = targetMemberID
        } else if let selected = await awaitMemberSelection(
            invocation: invocation,
            context: context,
            reason: "query_member_profile"
        ) {
            memberID = selected
        } else {
            return memberSelectionTimeoutResult(toolName: SparkToolName.queryMemberProfile.rawValue)
        }

        let data: SparkMedicalSyncAPI.RemoteMemberCompleteData
        do {
            data = try await medicalQueryAPI.fetchMemberCompleteData(memberID: memberID)
        } catch {
            return ToolExecutionResult(
                toolName: SparkToolName.queryMemberProfile,
                outputText: "成员医疗数据加载失败。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let member = data.member
        let cases = data.medicalCases ?? []
        let caseCount = cases.count
        let symptomCount = (data.symptoms ?? []).count
        let visitCount = (data.visits ?? []).count
        let surgeryCount = (data.surgeries ?? []).count
        let followUpCount = (data.followUps ?? []).count
        let healthExamCount = (data.healthExamReports ?? []).count
        let examCount = (data.examinationReports ?? []).count
        let examDetailCount = 0
        let reportCount = 0
        let medicineBoxCount = (data.medicineBoxes ?? []).count
        let prescriptionCount = (data.prescriptions ?? []).count
        let medicationPlanCount = (data.medicationPlans ?? []).count
        let medicationRecordCount = (data.todayMedicationRecords ?? []).count
        let daysNote = invocation.arguments["days"] ?? "3"
        let limitNote = invocation.arguments["limit"] ?? "3"

        let output = """
        query_type: \(queryType)
        参数提示：days=\(daysNote)（用药窗口）, limit=\(limitNote)（病例条数上限，Spark 当前汇总为全量计数）
        成员：\(member.name)
        关系：\(member.relationship)
        病例数：\(caseCount)
        症状数：\(symptomCount)
        就诊数：\(visitCount)
        手术数：\(surgeryCount)
        随访数：\(followUpCount)
        检查报告数：\(examCount)
        体检主表数：\(healthExamCount)
        医技明细数：\(examDetailCount)
        医疗报告数：\(reportCount)
        药箱药品数：\(medicineBoxCount)
        处方数：\(prescriptionCount)
        服药计划数：\(medicationPlanCount)
        今日服药记录数：\(medicationRecordCount)
        """

        return ToolExecutionResult(
            toolName: SparkToolName.queryMemberProfile,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true
        )
    }

}
