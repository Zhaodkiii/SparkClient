import SwiftUI

struct TaskPreviewSaveBottomBar: View {
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onSave) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSaving
                         ? NSLocalizedString("task.preview.saving", comment: "保存中...")
                         : NSLocalizedString("task.preview.save", comment: "保存任务"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

