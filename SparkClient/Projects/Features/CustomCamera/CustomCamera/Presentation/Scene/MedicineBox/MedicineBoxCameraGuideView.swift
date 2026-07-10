import SwiftUI

/// 用药 AI 拍照识别引导页。
struct MedicineBoxCameraGuideView: View {
    let onDismiss: () -> Void

    private var guideItems: [(title: String, detail: String)] {
        [
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.front.title", fallback: "药盒正面"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.front.detail",
                    fallback: "拍清楚药品名称、品牌、规格、包装数量"
                )
            ),
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.expiry.title", fallback: "保质期图片"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.expiry.detail",
                    fallback: "拍清楚生产日期、有效期、批号等信息"
                )
            ),
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.instruction.title", fallback: "说明书"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.instruction.detail",
                    fallback: "拍清楚用法用量、适应症、禁忌、注意事项"
                )
            )
        ]
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 92)

                illustration
                    .padding(.bottom, 24)

                Text(L10n.text("home.medical.medicine_box.camera.guide.title", fallback: "用药 AI 拍照识别"))
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(Color(uiColor: .label))
                    .padding(.bottom, 12)

                Text(L10n.text(
                    "home.medical.medicine_box.camera.guide.subtitle",
                    fallback: "拍摄前请准备好：\n1. 药盒正面图\n2. 保质期或生产日期图\n3. 药品说明书"
                ))
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundColor(Color(uiColor: .secondaryLabel))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                tipsCard
                    .padding(.horizontal, 28)

                Text(L10n.text(
                    "home.medical.medicine_box.camera.guide.disclaimer",
                    fallback: "识别结果请以药品包装和说明书为准"
                ))
                    .font(.system(.footnote, design: .default))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                Spacer()

                startButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 34)
            }

            VStack {
                HStack {
                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundColor(Color(uiColor: .systemBackground))
                            .frame(width: 50, height: 50)
                            .background(
                                Circle()
                                    .fill(Color(uiColor: .label))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                }

                Spacer()
            }
            .padding(.top, 52)
        }
    }
}

private extension MedicineBoxCameraGuideView {
    var illustration: some View {
        ZStack {
            MedicineBoxCameraViewfinderShape()
                .stroke(
                    Color(uiColor: .systemPurple),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 250, height: 200)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemPurple).opacity(0.12))
                .frame(width: 120, height: 88)

            Image(systemName: "pills.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(Color(uiColor: .systemPurple))
        }
        .frame(width: 260, height: 210)
    }

    var tipsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(guideItems.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(.headline, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .label))

                    Text(item.detail)
                        .font(.system(.subheadline, design: .default))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

                if index < guideItems.count - 1 {
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
            Text(L10n.text("home.medical.medicine_box.camera.guide.start", fallback: "开始拍摄"))
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
