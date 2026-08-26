import CoreLocation
import Foundation

extension ToolHub {
    private func makeSearchSummaryPayload(from response: WebSearchResponse) -> ChatSearchSummaryCardPayload {
        let references = response.items.map { item in
            ChatSearchSummaryReference(
                title: item.title.isEmpty ? item.url : item.title,
                url: item.url,
                snippet: item.snippet,
                sourceName: item.sourceName,
                publishedAt: item.publishedAt
            )
        }
        return ChatSearchSummaryCardPayload(
            providerName: response.providerName,
            query: response.query,
            keywords: searchSummaryKeywords(from: response.query),
            references: references,
            totalEstimatedMatches: response.totalEstimatedMatches
        )
    }

    private func searchSummaryKeywords(from query: String) -> [String] {
        let separators = CharacterSet(charactersIn: " /,，、\t\n")
        var seen = Set<String>()
        var keywords: [String] = []
        for rawPart in query.components(separatedBy: separators) {
            let keyword = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard keyword.isEmpty == false else { continue }
            let key = keyword.lowercased()
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            keywords.append(keyword)
            if keywords.count >= 12 { break }
        }
        return keywords
    }

    private func weatherConfigCard(for error: WeatherRuntimeError) -> ChatWeatherConfigCardPayload? {
        let actionTitle = L10n.text("ai_settings.weather.preview.open_settings", fallback: "去设置开启")
        switch error {
        case .disabled:
            return ChatWeatherConfigCardPayload(
                reason: .disabled,
                title: "天气查询未启用",
                message: "请先在 AI 设置里打开天气工具，再继续获取天气。",
                actionTitle: actionTitle
            )
        case .missingActiveProvider:
            return ChatWeatherConfigCardPayload(
                reason: .missingProvider,
                title: "还没有启用天气供应商",
                message: "请在天气工具设置里启用一个天气供应商，聊天才能继续获取实时天气。",
                actionTitle: actionTitle
            )
        case .missingAPIKey(let provider):
            return ChatWeatherConfigCardPayload(
                reason: .missingAPIKey,
                title: "\(provider) 还没配置好",
                message: "请先补充天气供应商的 API Key，再回来继续查询天气。",
                actionTitle: actionTitle
            )
        case .invalidEndpoint:
            return ChatWeatherConfigCardPayload(
                reason: .invalidEndpoint,
                title: "天气供应商配置有误",
                message: "当前天气服务地址无效，请检查天气工具里的供应商配置。",
                actionTitle: actionTitle
            )
        case .unsupportedProvider:
            return ChatWeatherConfigCardPayload(
                reason: .unsupportedProvider,
                title: "当前天气供应商暂不支持",
                message: "请切换到一个已支持的天气供应商后，再继续查询天气。",
                actionTitle: actionTitle
            )
        default:
            return nil
        }
    }

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
                "weather.query_start conversation=\(shortConversationID(context.threadID)) lat=\(String(format: "%.2f", latitude)) lon=\(String(format: "%.2f", longitude)) timeRange=\(timeRange)",
                module: .general
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
                "weather.query_result conversation=\(shortConversationID(context.threadID)) provider=\(config.provider.rawValue) condition=\(result.condition) temp=\(result.temperatureC.map { String(format: "%.1f", $0) } ?? "-") elapsedMs=\(elapsedMs)",
                module: .general
            )
            let markdown = result.markdown
            let baseResult = ToolExecutionResult(
                toolName: invocation.name,
                outputText: markdown,
                sensitive: true,
                shouldBypassModel: false,
                sideEffects: config.provider == .weatherKit ? [.weatherVisualization(result)] : []
            )
            return baseResult.withToolCallID(normalizedToolCallID(from: context))
        } catch {
            if let weatherError = error as? WeatherRuntimeError,
               let card = weatherConfigCard(for: weatherError) {
                return ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: weatherError.localizedDescription,
                    sensitive: false,
                    shouldBypassModel: false,
                    sideEffects: [.weatherConfigCard(card)]
                ).withToolCallID(normalizedToolCallID(from: context))
            }
            logger.warning(
                "weather.query_failed conversation=\(shortConversationID(context.threadID)) error=\(error.localizedDescription)",
                module: .general
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
        switch SparkLocationService.authorizationStatus() {
        case .notDetermined:
            guard let toolInteractionCoordinator else {
                return ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: "尚未获得定位授权，请询问用户所在城市，或引导用户开启位置权限后重试。",
                    sensitive: false,
                    shouldBypassModel: true
                )
            }
            let permissionResult = await toolInteractionCoordinator.requestLocationPermission(
                threadID: context.threadID,
                toolCallID: context.pendingToolCallID
            )
            switch permissionResult {
            case .success(let decision) where decision.authorized:
                break
            case .success(let decision):
                return locationPermissionDeniedResult(
                    invocation: invocation,
                    message: "用户未授权当前位置访问（\(decision.statusDescription)）。请改为询问用户所在城市，或说明需要到系统设置开启位置权限。",
                    includeSettingsCard: true
                )
            case .cancelled, .conflict:
                return ToolExecutionResult(
                    toolName: invocation.name,
                    outputText: "用户尚未完成位置授权。请继续当前对话，必要时询问用户所在城市。",
                    sensitive: false,
                    shouldBypassModel: false
                )
            }
        case .denied, .restricted:
            return locationPermissionDeniedResult(
                invocation: invocation,
                message: "当前应用没有位置权限，无法获取当前位置。请改为询问用户所在城市，或说明用户可在系统设置中开启位置权限。",
                includeSettingsCard: true
            )
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            return locationPermissionDeniedResult(
                invocation: invocation,
                message: "当前定位权限状态不可用，无法获取当前位置。请改为询问用户所在城市。",
                includeSettingsCard: false
            )
        }

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

    private func locationPermissionDeniedResult(
        invocation: ToolInvocation,
        message: String,
        includeSettingsCard: Bool
    ) -> ToolExecutionResult {
        let sideEffects: [ToolSideEffect]
        if includeSettingsCard {
            sideEffects = [
                .locationPermissionCards([
                    ChatLocationPermissionCard(
                        mode: .openSettings,
                        result: .denied,
                        status: .pending
                    )
                ])
            ]
        } else {
            sideEffects = []
        }
        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: message,
            sensitive: false,
            shouldBypassModel: false,
            sideEffects: sideEffects
        )
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
            let toolCallID = normalizedToolCallID(from: context)
            let rich = [
                ChatMessageBlock(
                    anchor: toolCallID.map(ChatBlockAnchor.toolCall),
                    kind: .searchSummary,
                    toolCallID: toolCallID,
                    parentToolCallID: toolCallID,
                    searchSummary: makeSearchSummaryPayload(from: combined)
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
