import Foundation

extension ToolHub {
    func runFetchSleep(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        // 取数前校验：成员是否绑定苹果健康设备（未选择成员时先弹选择卡片，等待用户选择后继续）；未绑定/无权限则按无数据处理并引导绑定。
        let accessCheck = await healthDataAccessCheck(
            invocation: invocation,
            context: context,
            toolName: .fetchSleepDetails
        )
        if let denied = accessCheck.denied {
            return denied
        }

        let range = resolveHealthRange(arguments: invocation.arguments, fallbackDays: 2)
        let startedAt = Date()
        let normalizedToolCallID = context.pendingToolCallID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let anchorToolCallID = normalizedToolCallID?.isEmpty == false ? normalizedToolCallID : nil

        logger.info(
            """
            fetch_sleep_details 开始执行：tool=\(invocation.name)，arguments=\(sleepLogArguments(invocation.arguments))，resolvedRange=\(sleepLogRange(range))，context=\(sleepLogContext(context, anchorToolCallID: anchorToolCallID))，fallbackDays=2，说明=将从 HealthKit 读取睡眠分析样本并生成睡眠详情/可视化卡片
            """,
            module: .aiConfig
        )

        do {
            let model = try await healthTool.fetchSleepDetails(from: range.start, to: range.end)
            // 仅向模型提供可读摘要；完整结构由协调器异步写入 `healthSleepVisualization`，不经工具输出再解码。
            let outputText = model.toReadableText()
            let containsUserData = healthOutputContainsUserData(outputText)

            logger.info(
                """
                fetch_sleep_details HealthKit 查询成功：\(sleepLogModelSummary(model))，outputTextLength=\(outputText.count)，elapsedMs=\(sleepElapsedMilliseconds(since: startedAt))，range=\(sleepLogRange(range))
                """,
                module: .aiConfig
            )

            var sideEffects: [ToolSideEffect] = []
            if containsUserData,
               context.threadID != nil,
               context.assistantMessageClientID != nil {
                logger.info(
                    """
                    fetch_sleep_details 将发布睡眠可视化卡片：anchorToolCallID=\(anchorToolCallID ?? "<nil>")，days=\(model.days.count)
                    """,
                    module: .aiConfig
                )
                sideEffects = [.sleepVisualization(model)]
            } else {
                let skipReason: String
                if containsUserData == false {
                    skipReason = "查询结果没有用户睡眠数据"
                } else {
                    skipReason = "缺少会话或助手消息绑定"
                }
                logger.warning(
                    """
                    fetch_sleep_details 跳过睡眠可视化卡片发布：原因=\(skipReason)，threadID=\(context.threadID?.uuidString ?? "<nil>")，assistantMessageClientID=\(context.assistantMessageClientID?.uuidString ?? "<nil>")，anchorToolCallID=\(anchorToolCallID ?? "<nil>")；文本结果仍会返回
                    """,
                    module: .aiConfig
                )
            }
            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: outputText,
                sensitive: containsUserData,
                shouldBypassModel: true,
                resolvedMemberID: accessCheck.resolvedMemberID,
                sideEffects: sideEffects
            )
        } catch {
            let diagnostic = sleepFailureDiagnostic(
                error: error,
                invocation: invocation,
                context: context,
                range: range,
                anchorToolCallID: anchorToolCallID,
                elapsedMs: sleepElapsedMilliseconds(since: startedAt)
            )
           print(error)
            logger.error(diagnostic.logMessage, module: .aiConfig)

            return ToolExecutionResult(
                toolName: SparkToolName.fetchSleepDetails,
                outputText: diagnostic.userMessage,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


}

private extension ToolHub {
    func sleepFailureDiagnostic(
        error: Error,
        invocation: ToolInvocation,
        context: ToolExecutionContext,
        range: (start: Date, end: Date),
        anchorToolCallID: String?,
        elapsedMs: Int
    ) -> (logMessage: String, userMessage: String) {
        let nsError = error as NSError
        let localized = error.localizedDescription
        let likelyReason = sleepLikelyFailureReason(localizedDescription: localized)
        let userInfo = sleepLogUserInfo(nsError.userInfo)

        let logMessage = """
        fetch_sleep_details 执行失败：localizedDescription=\(localized)，errorType=\(String(reflecting: type(of: error)))，nsErrorDomain=\(nsError.domain)，nsErrorCode=\(nsError.code)，nsErrorUserInfo=\(userInfo)，likelyReason=\(likelyReason)，tool=\(invocation.name)，arguments=\(sleepLogArguments(invocation.arguments))，resolvedRange=\(sleepLogRange(range))，context=\(sleepLogContext(context, anchorToolCallID: anchorToolCallID))，elapsedMs=\(elapsedMs)，排查顺序=1) 检查 HealthKit/Apple 健康是否可用；2) 检查睡眠分析读取授权；3) 检查查询区间是否包含睡眠样本；4) 检查 start_date/end_date 是否解析后被夹到未来或反向；5) 检查设备/模拟器是否真的有 Apple 健康睡眠数据；6) 若 domain/code 非 0，按 NSError domain/code 追踪系统或授权层错误
        """

        let userMessage = """
        睡眠查询失败：\(localized)
        查询区间：\(sleepDisplayDate(range.start)) 至 \(sleepDisplayDate(range.end))。
        失败原因判断：\(likelyReason)
        可能原因：HealthKit 不可用、未授权读取睡眠分析、该时间段没有睡眠样本、设备/模拟器没有 Apple 健康数据，或传入日期超出可查询范围。
        """

        return (logMessage, userMessage)
    }

    func sleepLikelyFailureReason(localizedDescription: String) -> String {
        let lowercased = localizedDescription.lowercased()

        if lowercased.contains("invalid") || localizedDescription.contains("无效") || localizedDescription.contains("日期") {
            return "查询日期范围无效或解析后 start_date 晚于 end_date"
        }
        if lowercased.contains("not available") || localizedDescription.contains("不可用") {
            return "当前设备、系统环境或 HealthKit 服务不可用"
        }
        if lowercased.contains("authorization") || lowercased.contains("permission") || localizedDescription.contains("授权") || localizedDescription.contains("权限") {
            return "Apple 健康读取权限不足，可能未允许读取睡眠分析"
        }
        if localizedDescription.contains("睡眠") || lowercased.contains("sleep") || localizedDescription.contains("没有") || localizedDescription.contains("未找到") {
            return "查询区间内没有可用睡眠分析样本，或样本被阶段过滤规则排除"
        }

        return "未命中特定错误分类，请结合 NSError domain/code/userInfo 和调用上下文继续排查"
    }

    func sleepLogArguments(_ arguments: [String: String]) -> String {
        guard arguments.isEmpty == false else { return "<empty>" }
        return arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    func sleepLogRange(_ range: (start: Date, end: Date)) -> String {
        "\(sleepLogDate(range.start))...\(sleepLogDate(range.end))"
    }

    func sleepLogContext(_ context: ToolExecutionContext, anchorToolCallID: String?) -> String {
        [
            "memberID=\(context.memberID.map(String.init) ?? "<nil>")",
            "locale=\(context.locale.identifier)",
            "threadID=\(context.threadID?.uuidString ?? "<nil>")",
            "assistantMessageClientID=\(context.assistantMessageClientID?.uuidString ?? "<nil>")",
            "pendingToolCallID=\(context.pendingToolCallID ?? "<nil>")",
            "anchorToolCallID=\(anchorToolCallID ?? "<nil>")",
            "providerCompany=\(context.providerCompany ?? "<nil>")",
            "modelName=\(context.modelName ?? "<nil>")",
            "endpoint=\(context.endpoint ?? "<nil>")",
            "pendingResumeMessages=\(context.pendingResumeMessages.count)"
        ].joined(separator: ",")
    }

    func sleepLogModelSummary(_ model: ChatHealthSleepModel) -> String {
        let days = model.days
        let totalSegments = days.reduce(0) { $0 + $1.timeline.count }
        let totalSleepMinutes = days.reduce(0) { $0 + $1.summary.totalSleepMinutes }
        let dayIDs = days.map(\.date).joined(separator: ",")
        return "schemaVersion=\(model.schemaVersion)，generatedAt=\(model.generatedAt)，days=\(days.count)，dayIDs=[\(dayIDs)]，totalSegments=\(totalSegments)，totalSleepMinutes=\(totalSleepMinutes)"
    }

    func sleepLogUserInfo(_ userInfo: [String: Any]) -> String {
        guard userInfo.isEmpty == false else { return "<empty>" }
        return userInfo
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    func sleepLogDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = Calendar.current.timeZone
        return formatter.string(from: date)
    }

    func sleepDisplayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.string(from: date)
    }

    func sleepElapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1000))
    }
}
