import SwiftUI

enum MemberNutritionBodyMetricPresentation {
    case embedded
    case fullScreen
}

private enum MemberNutritionHeroStyle {
    static let accentTint = Color(red: 0.38, green: 0.24, blue: 0.68)
    static let circleFill = Color(red: 0.61, green: 0.48, blue: 0.93)

    static func heroImage(_ name: String, isWideLayout: Bool) -> some View {
        Group {
            if isWideLayout {
                Image(name)
            } else {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
    }

    static func heroBackground(width: CGFloat, height: CGFloat) -> some View {
        Circle()
            .fill(circleFill)
            .scaleEffect(1.5)
            .frame(width: width, height: width)
            .offset(y: -height / (width < 750 ? 2 : 2.5))
    }

    static var heroBackground: some View {
        let bounds = UIScreen.main.bounds
        return heroBackground(width: bounds.width, height: bounds.height)
    }
}

private struct MemberNutritionHeroBackdrop<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                MemberNutritionHeroStyle.heroBackground
            }
    }
}

struct MemberNutritionHeightStepView: View {
    @Binding var heightCm: Double
    var presentation: MemberNutritionBodyMetricPresentation = .embedded

    var body: some View {
        MemberNutritionMetricStepView(
            title: "身高",
            value: $heightCm,
            unit: "cm",
            imageName: "heightMeasurement",
            tint: MemberNutritionHeroStyle.accentTint,
            range: 120...220,
            step: 1,
            majorStride: 10,
            presentation: presentation
        )
    }
}

struct MemberNutritionWeightStepView: View {
    @Binding var weightKg: Double
    var presentation: MemberNutritionBodyMetricPresentation = .embedded

    var body: some View {
        MemberNutritionWeightSliderStepView(
            weightKg: $weightKg,
            presentation: presentation
        )
    }
}

private struct MemberNutritionWeightSliderStepView: View {
    @Binding var weightKg: Double
    var presentation: MemberNutritionBodyMetricPresentation

    private let tint = MemberNutritionHeroStyle.accentTint

    var body: some View {
        switch presentation {
        case .embedded:
            embeddedBody
        case .fullScreen:
            fullScreenBody
        }
    }

    private var embeddedBody: some View {
        MemberNutritionHeroBackdrop {
            VStack(spacing: 26) {
                MemberNutritionHeroStyle.heroImage("excersize", isWideLayout: isWideLayout)

                valueSection

                sliderControl
                    .padding()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var fullScreenBody: some View {
        VStack(spacing: 15) {
            MemberNutritionHeroStyle.heroImage("excersize", isWideLayout: isWideLayout)
                .padding(.top, 32)

            Spacer(minLength: 0)

            valueSection
                .padding(.bottom, 20)

            sliderControl
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            MemberNutritionHeroStyle.heroBackground
        }
    }

    private var sliderControl: some View {
        SparkCustomRulerSlider(
            value: $weightKg,
            range: 30...150,
            step: 1,
            majorStride: 10,
            tint: tint
        )
        .frame(height: 50)
        .overlay(alignment: .top) {
            if presentation == .fullScreen {
                Rectangle()
                    .fill(Color.gray.opacity(0.45))
                    .frame(width: 1, height: 50)
                    .offset(y: -30)
            }
        }
    }

    private var valueSection: some View {
        VStack(spacing: 12) {
            Text("体重")
                .font(presentation == .fullScreen ? .title.weight(.heavy) : .title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayValue)
                    .font(
                        presentation == .fullScreen
                            ? .system(size: 38, weight: .heavy)
                            : .system(size: 42, weight: .bold, design: .rounded)
                    )
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .animation(.easeInOut(duration: 0.2), value: weightKg)

                Text("kg")
                    .font(presentation == .fullScreen ? .title3.weight(.heavy) : .title3.weight(.bold))
                    .foregroundStyle(tint)
            }
        }
    }

    private var isWideLayout: Bool {
        UIScreen.main.bounds.width >= 750
    }

    private var displayValue: String {
        if weightKg.rounded() == weightKg {
            return String(format: "%.0f", weightKg)
        }
        return String(format: "%.1f", weightKg)
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
    let presentation: MemberNutritionBodyMetricPresentation

    var body: some View {
        switch presentation {
        case .embedded:
            embeddedBody
        case .fullScreen:
            fullScreenBody
        }
    }

    private var embeddedBody: some View {
        MemberNutritionHeroBackdrop {
            VStack(spacing: 26) {
                MemberNutritionHeroStyle.heroImage(imageName, isWideLayout: isWideLayout)

                valueSection

                pickerControl
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var fullScreenBody: some View {
        VStack(spacing: 15) {
            MemberNutritionHeroStyle.heroImage(imageName, isWideLayout: isWideLayout)
                .padding(.top, 32)

            Spacer(minLength: 0)

            valueSection
                .padding(.bottom, 20)

            pickerControl
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            MemberNutritionHeroStyle.heroBackground
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(presentation == .fullScreen ? .title.weight(.heavy) : .title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayValue)
                    .font(
                        presentation == .fullScreen
                            ? .system(size: 38, weight: .heavy)
                            : .system(size: 42, weight: .bold, design: .rounded)
                    )
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .animation(.easeInOut(duration: 0.2), value: value)

                Text(unit)
                    .font(presentation == .fullScreen ? .title3.weight(.heavy) : .title3.weight(.bold))
                    .foregroundStyle(tint)
            }
        }
    }

    @ViewBuilder
    private var pickerControl: some View {
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
            .padding(.horizontal, presentation == .fullScreen ? 0 : 10)
        } else {
            SparkCustomRulerSlider(
                value: $value,
                range: range,
                step: step,
                majorStride: majorStride,
                tint: tint
            )
            .frame(height: 50)
            .overlay(alignment: .top) {
                if presentation == .fullScreen {
                    Rectangle()
                        .fill(Color.gray.opacity(0.45))
                        .frame(width: 1, height: 50)
                        .offset(y: -30)
                }
            }
            .padding(presentation == .fullScreen ? EdgeInsets() : EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    private var isWideLayout: Bool {
        UIScreen.main.bounds.width >= 750
    }

    private var displayValue: String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
