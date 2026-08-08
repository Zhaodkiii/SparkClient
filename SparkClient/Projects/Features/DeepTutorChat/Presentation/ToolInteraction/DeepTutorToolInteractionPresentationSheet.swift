import SwiftUI

struct DeepTutorToolInteractionPresentationSheet: View {
    let active: DeepTutorToolInteractionCoordinator.ActivePresentation
    @ObservedObject var coordinator: DeepTutorToolInteractionCoordinator

    var body: some View {
        switch active.snapshot {
        case .toolPreview(let prompt):
            DeepTutorToolPreviewSheet(
                prompt: prompt,
                onClose: { coordinator.dismissToolPreview(id: active.id) }
            )
        }
    }
}
