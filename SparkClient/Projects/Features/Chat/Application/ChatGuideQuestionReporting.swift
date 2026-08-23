import Foundation

/// AI 生成引导问题登记上送（后台异步 best-effort，失败不阻断主流程）。
protocol ChatGuideQuestionRegistrationReporting: Sendable {
    /// 登记一条或多条 AI 生成问题，返回 clientQuestionID → serverQuestionID 映射。
    func registerGeneratedQuestions(memberID: Int, questions: [ChatGuideQuestion]) async -> [String: Int]
}

/// 已登记引导问题点击上送（后台异步 best-effort，失败不阻断主流程）。
protocol ChatGuideQuestionClickReporting: Sendable {
    /// 上送单次点击，驱动服务端 click_count 原子递增。
    func reportClick(serverQuestionId: Int) async
}

extension SparkChatGuideQuestionAPI: ChatGuideQuestionRegistrationReporting {
    func registerGeneratedQuestions(memberID: Int, questions: [ChatGuideQuestion]) async -> [String: Int] {
        configuration.logger.info(
            "[CHATGUIDE-DEBUG][adapter] registerGeneratedQuestions enter memberID=\(memberID) count=\(questions.count)",
            module: .general
        )
        let items = questions.map {
            SparkChatGuideQuestionAPI.RegisterItem(
                id: $0.id,
                title: $0.title,
                prompt: $0.prompt,
                category: $0.category
            )
        }
        do {
            let result = try await register(memberId: memberID, items: items)
            configuration.logger.info(
                "[CHATGUIDE-DEBUG][adapter] registerGeneratedQuestions result=\(result)",
                module: .general
            )
            return result
        } catch {
            configuration.logger.warning(
                "[CHATGUIDE-DEBUG][adapter] registerGeneratedQuestions error=\(error)",
                module: .general
            )
            return [:]
        }
    }
}

extension SparkChatGuideQuestionAPI: ChatGuideQuestionClickReporting {
    func reportClick(serverQuestionId: Int) async {
        configuration.logger.info(
            "[CHATGUIDE-DEBUG][adapter] reportClick enter serverQuestionId=\(serverQuestionId)",
            module: .general
        )
        _ = try? await reportClick(serverQuestionId: serverQuestionId, memberId: nil)
    }
}