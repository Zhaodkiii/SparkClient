import SwiftUI

struct MemberSetupStepHeaderView: View {
    let title: String
    let subtitle: String
    let step: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title2.weight(.bold))
                Spacer()
                Text("\(step)/\(total)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }
}
