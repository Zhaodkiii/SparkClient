import Foundation

/// Phase 2 extension points:
/// - typed recognition result by mode
/// - attachment upload and business binding
/// - rich result pages and editable forms
enum MedicalDocumentUploadPhaseTwo {
    static let plannedCapabilities: [String] = [
        "mode_specific_prompts",
        "typed_result_models",
        "attachment_business_binding",
        "complex_result_pages",
        "category_specific_save_pipeline"
    ]
}
