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

    @State private var isLoaded = false
    private let scrollCoordinateSpaceName = "SparkHorizontalWheelPickerScroll"

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizontalPadding = size.width / 2

            ScrollView(.horizontal) {
                HStack(spacing: config.spacing) {
                    ForEach(0...config.totalSteps, id: \.self) { index in
                        let isMajor = config.isMajorStep(index)

                        Divider()
                            .background(isMajor ? Color.primary : .gray)
                            .frame(width: 0, height: isMajor ? 20 : 10, alignment: .center)
                            .frame(maxHeight: 20, alignment: .bottom)
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
                            .background {
                                if index == 0 {
                                    GeometryReader { markerProxy in
                                        Color.clear.preference(
                                            key: SparkHorizontalWheelLeadingMarkerXPreferenceKey.self,
                                            value: markerProxy.frame(in: .named(scrollCoordinateSpaceName)).midX
                                        )
                                    }
                                }
                            }
                    }
                }
                .frame(height: size.height)
                .scrollTargetLayout()
            }
            .coordinateSpace(name: scrollCoordinateSpaceName)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding<Int?>(
                get: {
                    isLoaded ? config.index(for: value) : nil
                },
                set: { newValue in
                    guard let newValue else { return }
                    value = config.value(for: newValue)
                }
            ))
            .overlay(alignment: .center) {
                Rectangle()
                    .frame(width: 1, height: 40)
                    .padding(.bottom, 20)
            }
            .safeAreaPadding(.horizontal, horizontalPadding)
            .onPreferenceChange(SparkHorizontalWheelLeadingMarkerXPreferenceKey.self) { leadingMarkerX in
                guard isLoaded, config.spacing > 0 else { return }

                let rawIndex = ((size.width / 2) - leadingMarkerX) / config.spacing
                let clampedIndex = min(max(Int(rawIndex.rounded()), 0), config.totalSteps)
                let resolvedValue = config.value(for: clampedIndex)

                if abs(resolvedValue - value) > 0.0001 {
                    value = resolvedValue
                }
            }
            .onAppear {
                if isLoaded == false {
                    value = config.value(for: config.index(for: value))
                    isLoaded = true
                }
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

@available(iOS 17.0, *)
private struct SparkHorizontalWheelLeadingMarkerXPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
