import Foundation

extension ToolHub {
    func runQueryMemberProfile(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let targetMemberID: Int? = {
            if let value = invocation.arguments["member_id"], let id = Int(value) {
                return id
            }
            if let value = invocation.arguments["patient_id"], let id = Int(value) {
                return id
            }
            return context.memberID
        }()
        let requestedFocus = [
            invocation.arguments["focus"],
            invocation.arguments["query_type"],
            invocation.arguments["intent"],
            invocation.arguments["purpose"],
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }

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

        let result = await MainActor.run {
            MemberProfileFormatter.makeAIResult(
                data: data,
                requestedFocus: requestedFocus
            )
        }
        let output = result.content

        return ToolExecutionResult(
            toolName: SparkToolName.queryMemberProfile,
            outputText: output,
            sensitive: true,
            shouldBypassModel: true,
            resolvedMemberID: memberID,
            arguments: normalizedQueryMemberProfileArguments(
                invocation: invocation,
                memberID: memberID,
                requestedFocus: requestedFocus,
                metadata: result.metadata
            )
        )
    }

    private func normalizedQueryMemberProfileArguments(
        invocation: ToolInvocation,
        memberID: Int,
        requestedFocus: String?,
        metadata: [String: String]
    ) -> [String: String] {
        var arguments = invocation.arguments
        arguments["member_id"] = String(memberID)
        if let requestedFocus, requestedFocus.isEmpty == false {
            arguments["focus"] = requestedFocus
        }
        for key in [
            "member_name",
            "relationship",
            "gender",
            "age",
            "medical_case_count",
            "symptom_count",
            "surgery_count",
            "follow_up_count",
            "health_exam_report_count",
            "examination_report_count",
            "medication_plan_count",
        ] {
            if let value = metadata[key] {
                arguments[key] = value
            }
        }
        return arguments
    }
}
