import Foundation

enum DeepTutorToolPromptManifestBuilder {
    static func manifest(from composition: DeepTutorToolRuntimeCompositionResult) -> String {
        composition.promptManifest
    }
}

