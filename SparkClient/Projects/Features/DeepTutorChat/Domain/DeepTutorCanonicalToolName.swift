import Foundation

/// DeepTutor-main canonical tool names（跨端事实源）。
nonisolated enum DeepTutorCanonicalToolName: String, CaseIterable, Sendable {
    case brainstorm
    case geogebraAnalysis = "geogebra_analysis"
    case webSearch = "web_search"
    case codeExecution = "code_execution"
    case reason
    case paperSearch = "paper_search"
    case imagegen
    case videogen

    case rag
    case kbFiles = "kb_files"
    case readSource = "read_source"
    case readMemory = "read_memory"
    case writeMemory = "write_memory"
    case readSkill = "read_skill"
    case listNotebook = "list_notebook"
    case writeNote = "write_note"
    case webFetch = "web_fetch"
    case github
    case exec
    case loadTools = "load_tools"
    case cron
    case askUser = "ask_user"
    case showCustomMessageCard = "show_custom_message_card"

    case masteryStatus = "mastery_status"
    case masteryQuiz = "mastery_quiz"
    case masteryGrade = "mastery_grade"
    case masteryAssess = "mastery_assess"
    case masteryBuild = "mastery_build"

    static var userToggleable: [String] {
        [
            brainstorm.rawValue,
            geogebraAnalysis.rawValue,
            webSearch.rawValue,
            codeExecution.rawValue,
            reason.rawValue,
            paperSearch.rawValue,
            imagegen.rawValue,
            videogen.rawValue,
        ]
    }

    static var configurableBuiltins: [String] {
        [
            rag.rawValue,
            kbFiles.rawValue,
            codeExecution.rawValue,
            readSource.rawValue,
            readMemory.rawValue,
            writeMemory.rawValue,
            readSkill.rawValue,
            listNotebook.rawValue,
            writeNote.rawValue,
            webFetch.rawValue,
            github.rawValue,
            exec.rawValue,
            loadTools.rawValue,
            cron.rawValue,
            askUser.rawValue,
            showCustomMessageCard.rawValue,
        ]
    }

    static var alwaysOnAutoMounts: [String] {
        [
            writeMemory.rawValue,
            webFetch.rawValue,
            github.rawValue,
            askUser.rawValue,
            showCustomMessageCard.rawValue,
            cron.rawValue,
        ]
    }
}
