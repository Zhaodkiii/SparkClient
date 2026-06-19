import SwiftUI

struct MemberNutritionHeightStepView: View {
    @Binding var heightCm: Double

    var body: some View {
        MemberNutritionMetricStepView(
            title: "身高",
            value: $heightCm,
            unit: "cm",
            imageName: "heightMeasurement",
            tint: Color(red: 0.38, green: 0.24, blue: 0.68),
            range: 120...220,
            step: 1,
            majorStride: 10
        )
    }
}

struct MemberNutritionWeightStepView: View {
    @Binding var weightKg: Double

    var body: some View {
        MemberNutritionMetricStepView(
            title: "体重",
            value: $weightKg,
            unit: "kg",
            imageName: "excersize",
            tint: Color(red: 0.38, green: 0.24, blue: 0.68),
            range: 30...150,
            step: 1,
            majorStride: 10
        )
    }
}

private struct MemberNutritionMetricStepView: View {
    let title: String
    @Binding var value: Double
    let unit: String
    let imageName: String
    let tint: Color
    let range: ClosedRange<Double>
    let step: Double
    let majorStride: Double

    var body: some View {
        VStack(spacing: 26) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.34), tint.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 260)

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayValue)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .animation(.easeInOut(duration: 0.2), value: value)

                    Text(unit)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint)
                }
            }

            if #available(iOS 17.0, *) {
                SparkHorizontalWheelPicker(
                    config: .init(
                        lowerBound: range.lowerBound,
                        upperBound: range.upperBound,
                        step: step,
                        majorStride: majorStride,
                        spacing: 10
                    ),
                    value: $value
                )
                    .frame(height: 74)
                    .padding(.horizontal, 10)
            } else {
                Slider(value: $value, in: range, step: step)
                    .tint(tint)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var displayValue: String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
