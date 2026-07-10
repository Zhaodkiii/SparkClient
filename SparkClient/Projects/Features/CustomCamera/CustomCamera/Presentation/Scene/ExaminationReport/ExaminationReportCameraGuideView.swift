import SwiftUI

/// 医疗报告拍摄引导页。
struct ExaminationReportCameraGuideView: View {
    let context: ExaminationReportCameraContext
    let maxCaptureCount: Int
    let onDismiss: () -> Void

    private var tips: [String] {
        [
            L10n.text(
                "home.medical.examination_report.camera.guide.tip.flat_surface",
                fallback: "将报告放在平整桌面上"
            ),
            L10n.text(
                "home.medical.examination_report.camera.guide.tip.full_frame",
                fallback: "保持纸张四边完整入框"
            ),
            L10n.text(
                "home.medical.examination_report.camera.guide.tip.no_glare",
                fallback: "避免反光、阴影和手指遮挡"
            ),
            L10n.text(
                "home.medical.examination_report.camera.guide.tip.clear_text",
                fallback: "拍清楚姓名、检查项目、时间、医院、所见和结论"
            ),
            String(
                format: L10n.text(
                    "home.medical.examination_report.camera.guide.tip.multi_page",
                    fallback: "多页报告可按顺序连续拍摄，本次最多 %d 张"
                ),
                locale: Locale.current,
                maxCaptureCount
            )
        ]
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 36)

                    illustration
                        .padding(.bottom, 24)

                    Text(context.guideTitle)
                        .font(.system(.largeTitle, design: .default).weight(.heavy))
                        .foregroundColor(Color(uiColor: .label))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

                    Text(context.guideSubtitle)
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)

                    tipsCard
                        .padding(.horizontal, 28)

                    Text(
                        L10n.text(
                            "home.medical.examination_report.camera.guide.disclaimer",
                            fallback: "识别结果请以报告原件为准"
                        )
                    )
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
                startButton
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(Color(uiColor: .systemBackground))
            }
        }
    }
}

private extension ExaminationReportCameraGuideView {
    var illustration: some View {
        ZStack {
            ExaminationReportCameraViewfinderShape()
                .stroke(
                    Color(uiColor: .systemBlue),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 200, height: 282)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .systemBlue).opacity(0.10))
                .frame(width: 150, height: 212)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(Color(uiColor: .systemBlue))
        }
        .frame(width: 220, height: 300)
    }

    var tipsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(uiColor: .systemBlue))
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

    var startButton: some View {
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
    }
}
