import SwiftUI

struct MedicineBoxDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? L10n.text("home.medical.medicine_box.not_filled") : value)
                .multilineTextAlignment(.trailing)
        }
    }
}
