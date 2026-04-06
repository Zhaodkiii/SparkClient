import SwiftUI

extension View {
    /// Convenience sheet presenter for unified file preview.
    func unifiedFilePreview(
        selection: Binding<FilePreviewInput?>,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(item: selection, onDismiss: onDismiss) { input in
            UnifiedFilePreview(input: input) {
                selection.wrappedValue = nil
            }
        }
    }
}
