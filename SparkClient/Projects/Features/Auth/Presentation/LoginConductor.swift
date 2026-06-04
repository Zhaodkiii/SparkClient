import SwiftUI

struct PhoneRegion: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let dial: String
    let flag: String
    let countryCode: String
}

let defaultRegions: [PhoneRegion] = [
    // 东亚
    .init(name: L10n.text("auth.region.cn"), dial: "+86", flag: "🇨🇳", countryCode: "CN"),
    .init(name: L10n.text("auth.region.hk"), dial: "+852", flag: "🇭🇰", countryCode: "HK"),
    .init(name: L10n.text("auth.region.tw"), dial: "+886", flag: "🇹🇼", countryCode: "TW"),
    .init(name: L10n.text("auth.region.jp"), dial: "+81", flag: "🇯🇵", countryCode: "JP"),
    .init(name: L10n.text("auth.region.kr"), dial: "+82", flag: "🇰🇷", countryCode: "KR"),
    .init(name: L10n.text("auth.region.mo"), dial: "+853", flag: "🇲🇴", countryCode: "MO"),

    // 东南亚
    .init(name: L10n.text("auth.region.sg"), dial: "+65", flag: "🇸🇬", countryCode: "SG"),
    .init(name: L10n.text("auth.region.my"), dial: "+60", flag: "🇲🇾", countryCode: "MY"),
    .init(name: L10n.text("auth.region.th"), dial: "+66", flag: "🇹🇭", countryCode: "TH"),
    .init(name: L10n.text("auth.region.id"), dial: "+62", flag: "🇮🇩", countryCode: "ID"),
    .init(name: L10n.text("auth.region.ph"), dial: "+63", flag: "🇵🇭", countryCode: "PH"),
    .init(name: L10n.text("auth.region.vn"), dial: "+84", flag: "🇻🇳", countryCode: "VN"),

    // 欧美
    .init(name: L10n.text("auth.region.us"), dial: "+1", flag: "🇺🇸", countryCode: "US"),
    .init(name: L10n.text("auth.region.ca"), dial: "+1", flag: "🇨🇦", countryCode: "CA"),
    .init(name: L10n.text("auth.region.uk"), dial: "+44", flag: "🇬🇧", countryCode: "GB"),
    .init(name: L10n.text("auth.region.de"), dial: "+49", flag: "🇩🇪", countryCode: "DE"),
    .init(name: L10n.text("auth.region.fr"), dial: "+33", flag: "🇫🇷", countryCode: "FR"),
    .init(name: L10n.text("auth.region.it"), dial: "+39", flag: "🇮🇹", countryCode: "IT"),
    .init(name: L10n.text("auth.region.es"), dial: "+34", flag: "🇪🇸", countryCode: "ES"),
    .init(name: L10n.text("auth.region.pt"), dial: "+351", flag: "🇵🇹", countryCode: "PT"),
    .init(name: L10n.text("auth.region.ru"), dial: "+7", flag: "🇷🇺", countryCode: "RU"),

    // 澳洲 / 新西兰
    .init(name: L10n.text("auth.region.au"), dial: "+61", flag: "🇦🇺", countryCode: "AU"),
    .init(name: L10n.text("auth.region.nz"), dial: "+64", flag: "🇳🇿", countryCode: "NZ"),

    // 中东 / 南亚
    .init(name: L10n.text("auth.region.in"), dial: "+91", flag: "🇮🇳", countryCode: "IN"),
    .init(name: L10n.text("auth.region.ae"), dial: "+971", flag: "🇦🇪", countryCode: "AE"),
    .init(name: L10n.text("auth.region.sa"), dial: "+966", flag: "🇸🇦", countryCode: "SA"),
    .init(name: L10n.text("auth.region.il"), dial: "+972", flag: "🇮🇱", countryCode: "IL"),

    // 其他常用
    .init(name: L10n.text("auth.region.ch"), dial: "+41", flag: "🇨🇭", countryCode: "CH"),
    .init(name: L10n.text("auth.region.se"), dial: "+46", flag: "🇸🇪", countryCode: "SE"),
    .init(name: L10n.text("auth.region.no"), dial: "+47", flag: "🇳🇴", countryCode: "NO"),
    .init(name: L10n.text("auth.region.dk"), dial: "+45", flag: "🇩🇰", countryCode: "DK"),
    .init(name: L10n.text("auth.region.ie"), dial: "+353", flag: "🇮🇪", countryCode: "IE")
]

struct PhoneLoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    @State private var regions: [PhoneRegion] = defaultRegions
    @State private var chosenRegion: PhoneRegion
    @State private var phone: String = ""
    @State private var isRequesting: Bool = false
    @State private var otpId: String?
    @State private var isApplyingAutoRegion: Bool = false

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        let country = SparkSystemInfo.shared.mostLikelyCountryCode
        let initial = defaultRegions.first { $0.countryCode == country }
            ?? defaultRegions.first { $0.countryCode == "CN" }
            ?? defaultRegions[0]
        _chosenRegion = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 20) {
            headerHero
            formPad
            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: otpId)
        .background(
            NavigationLink(
                isActive: Binding(
                    get: { otpId != nil },
                    set: { isPresented in
                        if isPresented == false {
                            otpId = nil
                        }
                    }
                )
            ) {
                if let otpId {
                    OTPVerifyView(viewModel: viewModel, region: chosenRegion, phone: phone, otpId: otpId)
                } else {
                    EmptyView()
                }
            } label: {
                EmptyView()
            }
            .hidden()
        )
    }

    private var headerHero: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemTeal)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "phone")
                    .symbolRenderingMode(.hierarchical)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 90, height: 90)
            .shadow(color: .black.opacity(0.1), radius: 14, y: 8)

            VStack(spacing: 6) {
                Text(L10n.text("auth.phone.hero_title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.text("auth.phone.hero_subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, 32)
        .padding(.horizontal)
    }

    private var formPad: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("auth.phone.field_title"))
                    .font(.footnote)
                    .fontWeight(.medium)
                HStack(spacing: 0) {
                    Menu {
                        ForEach(regions) { region in
                            Button("\(region.flag)  \(region.name)  \(region.dial)") {
                                chosenRegion = region
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(chosenRegion.flag).font(.title3)
                            Text(chosenRegion.dial)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()
                        .frame(height: 22)

                    TextField(L10n.text("auth.phone.placeholder"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .onChange(of: phone) { newValue in
                            applyAutoRegionAndStripPrefixIfNeeded(newValue)
                        }
                }
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.6))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal)

            Button(action: { requestOTP() }) {
                HStack {
                    if isRequesting { ProgressView().tint(.white) }
                    Text(L10n.text("auth.phone.send_otp"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemBlue))
            .disabled(!phoneIsLikelyValid || isRequesting)
            .padding(.horizontal)
        }
    }

    private var phoneIsLikelyValid: Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 6
    }

    /// 如果用户粘贴了完整的国际手机号（例如 +861538... / 00861538... / 861538...）
    /// 自动匹配并选中对应的国家/地区，同时从输入框中移除国家码
    /// 只保留国内号码用于显示（例如 1538...）
    private func applyAutoRegionAndStripPrefixIfNeeded(_ raw: String) {
        guard isApplyingAutoRegion == false else { return }
        isApplyingAutoRegion = true
        defer { isApplyingAutoRegion = false }

        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: raw,
            supportedDials: regions.map(\.dial)
        )
        guard let detected,
              let region = regions.first(where: { $0.dial == detected.dial }) else {
            return
        }

        chosenRegion = region
        phone = detected.nationalDigits
    }

    private func requestOTP() {
        guard phoneIsLikelyValid else { return }
        isRequesting = true
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: chosenRegion.dial).e164
            let response = await viewModel.sendOTP(phoneNumber: full)
            isRequesting = false
            if let response {
                otpId = response.otpID
            }
        }
    }
}

struct OTPVerifyView: View {
    @ObservedObject var viewModel: LoginViewModel
    let region: PhoneRegion
    let phone: String

    @State var otpId: String
    @State private var code: String = ""
    @State private var isVerifying: Bool = false
    @State private var countdown: Int = 60

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(L10n.text("auth.otp.title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(L10n.text("auth.otp.sent_to")) \(region.dial) \(maskedPhone())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 6)

            VerificationCodeField(code: $code, length: 6, onComplete: {
                verify()
            })
                .padding(.top, 6)

            if countdown > 0 {
                Text("\(L10n.text("auth.otp.resend_countdown")) \(countdown)s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Button(L10n.text("auth.otp.resend")) { resendOTP() }
                    .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(L10n.text("auth.otp.safety_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer()
        }
        .padding()
        .onAppear { startTimer() }
        .overlay(alignment: .bottom) {
            Button(action: { verify() }) {
                HStack {
                    if isVerifying { ProgressView().tint(.white) }
                    Text(L10n.text("auth.otp.verify_and_login"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemBlue))
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdown)
    }

    private func startTimer() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func resendOTP() {
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            let response = await viewModel.sendOTP(phoneNumber: full, isResend: true)
            if let response {
                otpId = response.otpID
                startTimer()
            }
        }
    }

    private func verify() {
        guard code.count == 6 else { return }
        guard isVerifying == false else { return }
        isVerifying = true
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            await viewModel.phoneLogin(phoneNumber: full, verificationCode: code, otpId: otpId)
            isVerifying = false
        }
    }

    private func maskedPhone() -> String {
        let trimmed = phone.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 7 else { return phone }
        let start = trimmed.prefix(3)
        let end = trimmed.suffix(2)
        return "\(start)****\(end)"
    }
}

#Preview("Phone Login - Light") {
    CompatibleNavigationContainer {
        PhoneLoginView(viewModel: AppContainer.preview.makeLoginViewModel())
    }
    .preferredColorScheme(.light)
}

#Preview("Phone Login - Dark") {
    CompatibleNavigationContainer {
        PhoneLoginView(viewModel: AppContainer.preview.makeLoginViewModel())
    }
    .preferredColorScheme(.dark)
}

#Preview("OTP Verify - Light") {
    CompatibleNavigationContainer {
        OTPVerifyView(
            viewModel: AppContainer.preview.makeLoginViewModel(),
            region: defaultRegions.first ?? .init(name: "CN", dial: "+86", flag: "🇨🇳", countryCode: "CN"),
            phone: "13800138000",
            otpId: "preview-otp-id"
        )
    }
    .preferredColorScheme(.light)
}

#Preview("OTP Verify - Dark") {
    CompatibleNavigationContainer {
        OTPVerifyView(
            viewModel: AppContainer.preview.makeLoginViewModel(),
            region: defaultRegions.first ?? .init(name: "CN", dial: "+86", flag: "🇨🇳", countryCode: "CN"),
            phone: "13800138000",
            otpId: "preview-otp-id"
        )
    }
    .preferredColorScheme(.dark)
}
