import SwiftUI

@available(iOS 17.0, *)
struct SparkHorizontalWheelPicker: View {
    struct Config: Equatable {
        var lowerBound: Double
        var upperBound: Double
        var step: Double = 1
        var majorStride: Double = 10
        var spacing: CGFloat = 5
        var showsText: Bool = true

        var totalSteps: Int {
            guard step > 0, upperBound >= lowerBound else { return 0 }
            return Int(((upperBound - lowerBound) / step).rounded())
        }

        func value(for index: Int) -> Double {
            lowerBound + Double(index) * step
        }

        func index(for value: Double) -> Int {
            guard step > 0 else { return 0 }
            let clamped = min(max(value, lowerBound), upperBound)
            return Int(((clamped - lowerBound) / step).rounded())
        }

        func isMajorStep(_ index: Int) -> Bool {
            guard step > 0, majorStride > 0 else { return false }
            let ratio = majorStride / step
            let majorStep = max(Int(ratio.rounded()), 1)
            return index % majorStep == 0
        }
    }

    var config: Config
    @Binding var value: Double

    @State private var scrollPosition: Int?
    @State private var didApplyInitialPosition = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizontalPadding = size.width / 2
            let tickWidth = max(config.spacing, 1)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(0...config.totalSteps, id: \.self) { index in
                        tickMarkView(for: index, tickWidth: tickWidth)
                    }
                }
                .frame(height: size.height)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition)
            .overlay(alignment: .center) {
                Rectangle()
                    .frame(width: 1, height: 40)
                    .padding(.bottom, 20)
            }
            .safeAreaPadding(.horizontal, horizontalPadding)
            .onAppear {
                applyInitialPositionIfNeeded()
            }
            .onChange(of: value) { _, newValue in
                guard didApplyInitialPosition else { return }

                let resolvedIndex = config.index(for: newValue)
                let normalizedValue = config.value(for: resolvedIndex)

                if abs(value - normalizedValue) > 0.0001 {
                    value = normalizedValue
                }
                if scrollPosition != resolvedIndex {
                    scrollPosition = resolvedIndex
                }
            }
            .onChange(of: scrollPosition) { _, newPosition in
                guard didApplyInitialPosition, let newPosition else { return }

                let resolvedIndex = min(max(newPosition, 0), config.totalSteps)
                if scrollPosition != resolvedIndex {
                    scrollPosition = resolvedIndex
                    return
                }

                updateValue(for: resolvedIndex)
            }
            .onChange(of: config) { _, newConfig in
                didApplyInitialPosition = false

                let resolvedIndex = newConfig.index(for: value)
                let normalizedValue = newConfig.value(for: resolvedIndex)

                if abs(value - normalizedValue) > 0.0001 {
                    value = normalizedValue
                }
                if scrollPosition != resolvedIndex {
                    scrollPosition = resolvedIndex
                }
                didApplyInitialPosition = true
            }
        }
    }

    private func applyInitialPositionIfNeeded() {
        guard didApplyInitialPosition == false else { return }

        let resolvedIndex = config.index(for: value)
        let normalizedValue = config.value(for: resolvedIndex)

        if abs(value - normalizedValue) > 0.0001 {
            value = normalizedValue
        }
        if scrollPosition != resolvedIndex {
            scrollPosition = resolvedIndex
        }
        didApplyInitialPosition = true
    }

    private func updateValue(for index: Int) {
        let resolvedValue = config.value(for: index)
        if abs(resolvedValue - value) > 0.0001 {
            value = resolvedValue
        }
    }

    @ViewBuilder
    private func tickMarkView(for index: Int, tickWidth: CGFloat) -> some View {
        let isMajor = config.isMajorStep(index)

        VStack(spacing: 0) {
            Rectangle()
                .fill(isMajor ? Color.primary : .gray)
                .frame(width: 1, height: isMajor ? 20 : 10)
        }
        .frame(width: tickWidth, height: 20, alignment: .bottom)
        .overlay(alignment: .bottom) {
            if isMajor && config.showsText {
                Text(labelText(for: config.value(for: index)))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textScale(.secondary)
                    .fixedSize()
                    .offset(y: 20)
            }
        }
    }

    private func labelText(for value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
