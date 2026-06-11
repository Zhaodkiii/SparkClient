import SwiftUI

struct NutritionFoodCameraGuideView: View {
    let onDismiss: () -> Void

    private let tips = [
        "餐点不应超出镜头范围",
        "清晰展示每个物品",
        "确保光线充足"
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 92)

                illustration
                    .padding(.bottom, 28)

                Text("快照前须知小窍门")
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(Color(uiColor: .label))
                    .padding(.bottom, 28)

                tipsCard
                    .padding(.horizontal, 28)

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

private extension NutritionFoodCameraGuideView {
    var illustration: some View {
        ZStack {
            NutritionFoodCameraViewfinderShape()
                .stroke(
                    Color(uiColor: .systemMint),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 290, height: 220)

            Circle()
                .fill(Color(uiColor: .systemYellow).opacity(0.7))
                .frame(width: 150, height: 150)

            Text("🥗")
                .font(.system(size: 92))
        }
        .frame(width: 300, height: 230)
    }

    var tipsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                HStack(spacing: 18) {
                    Circle()
                        .fill(Color(uiColor: .systemPurple))
                        .frame(width: 8, height: 8)

                    Text(tip)
                        .font(.system(.title3, design: .default).weight(.bold))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 28)
                .frame(height: 88)

                if index < tips.count - 1 {
                    Divider()
                        .background(Color(uiColor: .separator))
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
            Text("开始拍摄")
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
