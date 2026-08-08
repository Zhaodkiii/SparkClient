import Foundation

enum DeepTutorToolSchemaBuilder {
    static func schemas(from composition: DeepTutorToolRuntimeCompositionResult) -> [AIRuntimeToolDefinition] {
        composition.schemas
    }
}

