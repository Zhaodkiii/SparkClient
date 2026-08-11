import SwiftUI

struct TaskDetailBottomActionBar: View {
    let isSubmitting: Bool
    let onDone: () -> Void
    let onSkip: () -> Void
    let onFail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(NSLocalizedString("task.action.complete", comment: "标记完成"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)

            Menu {
                Button(NSLocalizedString("task.action.skip", comment: "跳过")) {
                    onSkip()
                }
                Button(NSLocalizedString("task.action.fail", comment: "失败"), role: .destructive) {
                    onFail()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}
