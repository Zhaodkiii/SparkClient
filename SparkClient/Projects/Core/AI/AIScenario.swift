import Foundation

enum AIScenario: String, Codable, CaseIterable, Sendable {
    case chat
    case optimizationText = "optimization_text"
    case optimizationVisual = "optimization_visual"
    case contextFolding = "context_folding"
    case router
    case modelConfig = "model_config"
    case reportInterpretation = "report_interpretation"
}
