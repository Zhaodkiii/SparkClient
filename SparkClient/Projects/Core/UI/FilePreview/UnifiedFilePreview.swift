import SwiftUI
import UIKit

/// Reusable file preview container for feature screens.
/// It handles preview routing only and does not perform upload/download business logic.
struct UnifiedFilePreview: View {
    let input: FilePreviewInput
    var onClose: (() -> Void)?

    var body: some View {
        NavigationView {
            content
                .navigationTitle(input.resolvedDisplayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            onClose?()
                        }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var content: some View {
        if input.isLocalFileAvailable == false {
            fallbackView(
                systemImage: "exclamationmark.triangle",
                title: "Preview unavailable",
                message: "The selected file is missing or cannot be accessed."
            )
        } else if input.isImage {
//            imagePreview(for: input.fileURL)
            QuickLookPreviewBridge(inputs: [input], startIndex: 0, onDismiss: onClose)
                .ignoresSafeArea()
        } else {
            QuickLookPreviewBridge(inputs: [input], startIndex: 0, onDismiss: onClose)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func imagePreview(for url: URL) -> some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()

            if url.isFileURL {
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                } else {
                    fallbackView(
                        systemImage: "photo",
                        title: "Preview unavailable",
                        message: "Unable to decode this image."
                    )
                }
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    case .failure:
                        fallbackView(
                            systemImage: "photo",
                            title: "Preview unavailable",
                            message: "Unable to load this image."
                        )
                    @unknown default:
                        fallbackView(
                            systemImage: "photo",
                            title: "Preview unavailable",
                            message: "Unable to load this image."
                        )
                    }
                }
            }
        }
    }

    private func fallbackView(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
            Text(title)
                .font(.body.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }
}
