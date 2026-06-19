import SwiftUI

struct MemberSetupSkipButton: View {
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(title, action: onTap)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
    }
}
