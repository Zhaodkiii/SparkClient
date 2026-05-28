import SwiftUI

/// 规范化手机号输入（登录、远程邀请等共用，§18.8）。
struct PhoneNumberInputModel: Equatable {
    var rawInput: String = ""
    var countryCode: String = "+86"
    var nationalNumber: String = ""
    var e164: String = ""
    var isValid: Bool = false
}

struct PhoneNumberInputView: View {
    @Binding var model: PhoneNumberInputModel
    var regions: [PhoneRegion] = defaultRegions

    @FocusState private var isFocused: Bool
    @State private var chosenRegion: PhoneRegion = defaultRegions.first ?? .init(name: "", dial: "+86", flag: "🇨🇳")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(regions) { region in
                        Button("\(region.flag)  \(region.name)  \(region.dial)") {
                            chosenRegion = region
                            recompute()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(chosenRegion.flag).font(.title3)
                        Text(chosenRegion.dial)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                TextField(L10n.text("auth.phone.placeholder"), text: $model.rawInput)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .onChange(of: model.rawInput) { _ in recompute() }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done")) {
                    isFocused = false
                }
            }
        }
        .onAppear {
            if !model.countryCode.isEmpty {
                chosenRegion = regions.first { $0.dial == model.countryCode } ?? chosenRegion
            }
            recompute()
        }
    }

    private func recompute() {
        let raw = model.rawInput
        let dial = chosenRegion.dial
        let normalized = PhoneNumberNormalizer.normalize(rawInput: raw, defaultDial: dial)
        let e164 = normalized.e164
        let national = normalized.nationalDigits
        let isValid = national.count >= 7 && national.count <= 15
        model = PhoneNumberInputModel(
            rawInput: raw,
            countryCode: dial,
            nationalNumber: national,
            e164: e164,
            isValid: isValid
        )
    }
}
