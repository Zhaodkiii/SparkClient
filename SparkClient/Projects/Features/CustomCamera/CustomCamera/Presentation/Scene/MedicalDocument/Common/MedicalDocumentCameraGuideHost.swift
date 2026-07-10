import SwiftUI

/// 医疗文档拍摄引导页公共容器；具体说明内容由业务 GuideContent 注入。
struct MedicalDocumentCameraGuideHost<Illustration: View, Tips: View>: View {
    let title: String
    let subtitle: String
    let disclaimer: String
    let onDismiss: () -> Void
    @ViewBuilder let illustration: () -> Illustration
    @ViewBuilder let tips: () -> Tips

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 36)

                    illustration()
                        .padding(.bottom, 24)

                    Text(title)
                        .font(.system(.largeTitle, design: .default).weight(.heavy))
                        .foregroundColor(Color(uiColor: .label))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

                    Text(subtitle)
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)

                    tips()
                        .padding(.horizontal, 28)

                    Text(disclaimer)
                        .font(.system(.footnote, design: .default))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundColor(Color(uiColor: .systemBackground))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .label))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onDismiss) {
                    Text(L10n.text("home.medical.examination_report.camera.guide.start", fallback: "开始拍摄"))
                        .font(.system(.headline, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .label))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color(uiColor: .systemBackground))
            }
        }
    }
}

/// 引导页通用 tip 列表卡片。
struct MedicalDocumentCameraGuideTipsCard: View {
    let tips: [String]
    let accentColor: Color

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(spacing: 14) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)

                    Text(tip)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                if index < tips.count - 1 {
                    Divider()
                        .padding(.leading, 22)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 2)
        }
    }
}
