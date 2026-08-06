import Foundation

extension ToolHub {
    func runExternalConnectorTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        if invocation.name == SparkToolName.searchOnline.rawValue || invocation.name == SparkToolName.searchArxivPapers.rawValue {
            return await runWebSearchTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.readWebPage.rawValue || invocation.name == SparkToolName.extractRemoteFileContent.rawValue {
            return await runReadWebPageTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.queryWeather.rawValue {
            return await runWeatherTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.queryLocation.rawValue {
            return await runLocationTool(invocation: invocation, context: context)
        }

        if invocation.name == SparkToolName.getCurrentLocation.rawValue {
            return await runCurrentLocationTool(invocation: invocation, context: context)
        }

        let snapshot = await aiConfigCenter.currentSnapshot()
        let endpoint = resolveEndpoint(for: invocation.name, toolKeys: snapshot.toolKeys)
        let payloadSummary = invocation.arguments
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")

        let output = """
        工具 \(invocation.name) 已接入 SparkClient 路由。
        endpoint=\(endpoint ?? "未配置")
        args=\(payloadSummary.isEmpty ? "<empty>" : payloadSummary)
        当前为本地执行占位；如需真实联网调用，请在对应 toolClass 网关实现 HTTP 适配。
        """
        let rich = makeExternalConnectorRichBlocks(
            invocation: invocation,
            toolOutputForWebPreview: output,
            toolCallID: normalizedToolCallID(from: context)
        )
        return returnWithRichBlockSideEffects(
            context: context,
            result: ToolExecutionResult(
                toolName: invocation.name,
                outputText: output,
                sensitive: false,
                shouldBypassModel: true
            ),
            richBlocks: rich
        )
    }

    func runWeatherTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let latitude = Double(invocation.arguments["latitude"] ?? "")
        let longitude = Double(invocation.arguments["longitude"] ?? "")
        let timeRange = (invocation.arguments["timeRange"] ?? invocation.arguments["time_range"] ?? "today")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let locationName = invocation.arguments["locationName"] ?? invocation.arguments["location_name"]

        guard let latitude, let longitude else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: WeatherRuntimeError.missingCoordinates.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let started = Date()
        do {
            let config = try await aiConfigCenter.effectiveWeatherConfig()
            logger.info(
                "deeptutor.weather.query_start conversation=\(shortConversationID(context.threadID)) lat=\(String(format: "%.2f", latitude)) lon=\(String(format: "%.2f", longitude)) timeRange=\(timeRange)",
                module: .deepTutorChat
            )
            let result = try await weatherGateway.queryWeather(
                latitude: latitude,
                longitude: longitude,
                timeRange: timeRange.isEmpty ? "today" : timeRange,
                locationName: locationName,
                config: config
            )
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.info(
                "deeptutor.weather.query_result conversation=\(shortConversationID(context.threadID)) provider=\(config.provider.rawValue) condition=\(result.condition) temp=\(result.temperatureC.map { String(format: "%.1f", $0) } ?? "-") elapsedMs=\(elapsedMs)",
                module: .deepTutorChat
            )
            let markdown = result.markdown
            let rich = makeWeatherRichBlocks(
                result: result,
                toolCallID: normalizedToolCallID(from: context)
            )
            return returnWithRichBlockSideEffects(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: markdown,
                    sensitive: true,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            logger.warning(
                "deeptutor.weather.query_failed conversation=\(shortConversationID(context.threadID)) error=\(error.localizedDescription)",
                module: .deepTutorChat
            )
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    func runLocationTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let keyword = (invocation.arguments["keyword"] ?? invocation.arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: WeatherRuntimeError.emptyKeyword.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let config = try await aiConfigCenter.effectiveWeatherConfig()
            let result = try await weatherGateway.geocode(keyword: keyword, config: config)
            let output = """
            地点解析结果
            名称：\(result.name)
            纬度：\(String(format: "%.4f", result.latitude))
            经度：\(String(format: "%.4f", result.longitude))
            国家/地区：\(result.country ?? "-")
            """
            var args = invocation.arguments
            args["keyword"] = keyword
            args["latitude"] = String(result.latitude)
            args["longitude"] = String(result.longitude)
            let richInvocation = ToolInvocation(name: invocation.name, arguments: args)
            let rich = makeExternalConnectorRichBlocks(
                invocation: richInvocation,
                toolOutputForWebPreview: output,
                toolCallID: normalizedToolCallID(from: context)
            )
            return returnWithRichBlockSideEffects(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: output,
                    sensitive: true,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

    func runCurrentLocationTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        do {
            let coordinate = try await SparkLocationService.currentCoordinate()
            let output = """
            当前位置
            纬度：\(String(format: "%.4f", coordinate.latitude))
            经度：\(String(format: "%.4f", coordinate.longitude))
            """
            var args = invocation.arguments
            args["query"] = "local"
            args["latitude"] = String(coordinate.latitude)
            args["longitude"] = String(coordinate.longitude)
            let richInvocation = ToolInvocation(name: invocation.name, arguments: args)
            let rich = makeExternalConnectorRichBlocks(
                invocation: richInvocation,
                toolOutputForWebPreview: output,
                toolCallID: normalizedToolCallID(from: context)
            )
            return returnWithRichBlockSideEffects(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: output,
                    sensitive: true,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


    func runWebSearchTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? invocation.arguments["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: SearchRuntimeError.emptyQuery.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let config = try await aiConfigCenter.effectiveSearchConfig()
            let primary = try await webSearchGateway.search(query: query, config: config)
            let combined = try await mergedBilingualSearchIfNeeded(primary: primary, query: query, config: config)
            let combinedMarkdown = combined.markdown
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: combinedMarkdown,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithRichBlockSideEffects(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: combinedMarkdown,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }


    func runReadWebPageTool(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let url = (invocation.arguments["url"] ?? invocation.arguments["link"] ?? invocation.arguments["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.isEmpty == false else {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: "网页读取失败：url 不能为空。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        do {
            let text = try await webSearchGateway.readWebPage(urlString: url)
            let output = "网页读取结果\nURL: \(url)\n\n\(text)"
            let rich = [
                ChatMessageBlock(
                    anchor: normalizedToolCallID(from: context).map(ChatBlockAnchor.toolCall),
                    kind: .html,
                    text: output,
                    toolCallID: normalizedToolCallID(from: context)
                )
            ]
            return returnWithRichBlockSideEffects(
                context: context,
                result: ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: output,
                    sensitive: false,
                    shouldBypassModel: false
                ),
                richBlocks: rich
            )
        } catch {
            return ToolExecutionResult(
                toolName: invocation.name,
                outputText: error.localizedDescription,
                sensitive: false,
                shouldBypassModel: true
            )
        }
    }

}
