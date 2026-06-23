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
                    }
                }
                .frame(height: size.height)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding<Int?>(
                get: {
                    scrollPosition
                },
                set: { newValue in
                    guard let newValue else {
                        scrollPosition = nil
                        return
                    }

                    let resolvedIndex = min(max(newValue, 0), config.totalSteps)
                    scrollPosition = resolvedIndex
                    updateValue(for: resolvedIndex)
                }
            ))
            .overlay(alignment: .center) {
                Rectangle()
                    .frame(width: 1, height: 40)
                    .padding(.bottom, 20)
            }
            .safeAreaPadding(.horizontal, horizontalPadding)
            .onAppear {
                applyInitialPositionIfNeeded()
            }
            .task(id: config) {
                await applyInitialPositionAfterLayout()
            }
            .onChange(of: value) { _, newValue in
                guard didApplyInitialPosition else { return }

                let resolvedIndex = config.index(for: newValue)
                if scrollPosition != resolvedIndex {
                    scrollPosition = resolvedIndex
                }
            }
            .onChange(of: config) { _, newValue in
                let resolvedIndex = newValue.index(for: newValue.lowerBound)
                value = newValue.value(for: resolvedIndex)
                scrollPosition = resolvedIndex
            }
        }
    }

    private func applyInitialPositionIfNeeded() {
        guard didApplyInitialPosition == false else { return }

        let resolvedIndex = config.index(for: value)
        value = config.value(for: resolvedIndex)
        scrollPosition = resolvedIndex
        didApplyInitialPosition = true
    }

    private func applyInitialPositionAfterLayout() async {
        let resolvedIndex = config.index(for: value)

        await Task.yield()
        guard Task.isCancelled == false else { return }

        scrollPosition = nil

        await Task.yield()
        guard Task.isCancelled == false else { return }

        value = config.value(for: resolvedIndex)
        scrollPosition = resolvedIndex
    }

    private func updateValue(for index: Int) {
        let resolvedValue = config.value(for: index)
        if abs(resolvedValue - value) > 0.0001 {
            value = resolvedValue
        }
    }

    private func labelText(for value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
