import SwiftUI

struct ShareIconButton: View {
    let systemImage: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 2)
                                .padding(-3)
                        }
                    }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 72)
        }
        .buttonStyle(.plain)
    }
}
