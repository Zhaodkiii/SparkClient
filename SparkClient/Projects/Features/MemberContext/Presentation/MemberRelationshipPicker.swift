import SwiftUI

struct MemberRelationshipPicker: View {
    @Binding var relationshipCode: String
    @Binding var customRelationship: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("home.members.binding.relationship.title"))
                .font(.headline)

            ForEach(MemberRelationshipCatalog.rows, id: \.self) { rowCodes in
                HStack(spacing: 8) {
                    ForEach(rowCodes, id: \.self) { code in
                        let option = MemberRelationshipCatalog.option(for: code)
                        Button {
                            relationshipCode = code
                        } label: {
                            Text(option.title)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(relationshipCode == code ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if relationshipCode == "other" {
                TextField(
                    L10n.text("home.members.binding.relationship.other_placeholder"),
                    text: $customRelationship
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
