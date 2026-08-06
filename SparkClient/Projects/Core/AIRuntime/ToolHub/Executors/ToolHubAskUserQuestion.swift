import Foundation

extension ToolHub {
    func runAskUserQuestion(invocation: ToolInvocation, context: ToolExecutionContext) async -> ToolExecutionResult {
        let questions = parseQuestionItems(arguments: invocation.arguments)
        guard questions.isEmpty == false else {
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】ask_user_question 参数无效：需提供 1-5 个问题；选项式追问需 1-5 个选项，自由输入追问需 allows_other=true。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        if context.preferInlineAskUser {
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】已在消息内展示追问卡片，等待用户作答。",
                sensitive: false,
                shouldBypassModel: false,
                isAwaitingUserInput: true,
                arguments: invocation.arguments
            )
        }

        guard let toolInteractionCoordinator else {
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】当前界面无法展示问题选择 sheet，请直接向用户提问。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let prompt = ToolQuestionPrompt(questions: questions)
        let answerResult = await toolInteractionCoordinator.requestQuestionAnswer(
            threadID: context.threadID,
            prompt: prompt
        )
        let answer: ToolQuestionAnswer
        switch answerResult {
        case .success(let value):
            answer = value
        case .cancelled, .conflict:
            return ToolExecutionResult(
                toolName: SparkToolName.askUserQuestion,
                outputText: "【系统】用户取消或未提交问题选择。请继续当前对话，必要时用自然语言重新询问。",
                sensitive: false,
                shouldBypassModel: true,
                isAwaitingUserInput: true
            )
        }

        let output = formatQuestionAnswerText(questions: questions, responses: answer.responses)
        return ToolExecutionResult(
            toolName: SparkToolName.askUserQuestion,
            outputText: output,
            sensitive: false,
            shouldBypassModel: true
        )
    }
}
