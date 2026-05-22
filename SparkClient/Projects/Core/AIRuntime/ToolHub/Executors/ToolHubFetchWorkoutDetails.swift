import Foundation

extension ToolHub {
    func runFetchWorkout(
        invocation: ToolInvocation,       // AI 工具调用参数（时间、类型、数量）
        context: ToolExecutionContext     // 执行上下文（会话ID、消息ID等）
    ) async -> ToolExecutionResult {       // 返回给AI的工具执行结果
        
        // MARK: 1. 解析AI传入的参数
        // 解析时间范围：今天/本周/本月/自定义时间
        let range = resolveHealthRange(arguments: invocation.arguments)
        // 解析运动类型：running / cycling / swimming 等
        let types = parseStringList(invocation.arguments["types"])
        // 解析最大返回条数，默认100
        let maxItems = parseIntValue(invocation.arguments["max_items"] ?? "") ?? 100

        do {
            // MARK: 2. 核心：调用 HealthTool 查询健康数据
            // 从 HealthKit 读取运动记录 → 转为 ChatHealthWorkoutModel
            let model = try await healthTool.fetchWorkoutDetails(
                from: range.start,
                to: range.end,
                types: types,
                maxItems: maxItems
            )
            
            var sideEffects: [ToolSideEffect] = []
            if model.workouts.isEmpty == false,
               context.threadID != nil,
               context.assistantMessageClientID != nil {
                sideEffects = [.workoutVisualization(model)]
            }

            // MARK: 4. 返回【可读文本】给AI
            // 把结构化运动数据 → 自然语言文字，让AI直接朗读/展示
            return ToolExecutionResult(
                toolName: SparkToolName.fetchWorkoutDetails,
                outputText: healthNoDataDiagnosticIfNeeded(model.toReadableText(), range: range),
                sensitive: true,                     // 健康数据 = 敏感数据
                shouldBypassModel: true,             // 不再回传给大模型，直接展示
                sideEffects: sideEffects
            )
        } catch {
            // MARK: 5. 异常处理：查询失败时返回错误信息
            return ToolExecutionResult(
                toolName: SparkToolName.fetchWorkoutDetails,
                outputText: "运动记录查询失败：\(error.localizedDescription)",
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


}
