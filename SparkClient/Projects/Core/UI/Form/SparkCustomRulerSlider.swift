import SwiftUI
import UIKit

struct SparkCustomRulerSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var majorStride: Double = 10
    var tint: Color = .accentColor
    var tickSpacing: CGFloat = 20

    var body: some View {
        SparkCustomRulerScrollView(
            value: $value,
            range: range,
            step: step,
            majorStride: majorStride,
            tint: tint,
            tickSpacing: tickSpacing
        )
        .overlay {
            Rectangle()
                .fill(Color.gray)
                .frame(width: 1, height: 50)
                .offset(y: -30)
        }
    }
}

private struct SparkCustomRulerScrollView: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var majorStride: Double
    var tint: Color
    var tickSpacing: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let hostingController = UIHostingController(rootView: rulerContent)
        hostingController.view.backgroundColor = .clear
        scrollView.addSubview(hostingController.view)
        context.coordinator.hostingController = hostingController

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostingController?.rootView = rulerContent

        let contentWidth = CGFloat(totalSteps + 1) * tickSpacing
        let frame = CGRect(x: 0, y: 0, width: contentWidth, height: 50)
        context.coordinator.hostingController?.view.frame = frame
        scrollView.contentSize = frame.size
        scrollView.contentInset = contentInset(for: scrollView)

        guard scrollView.isDragging == false, scrollView.isDecelerating == false else { return }
        let targetOffset = contentOffset(for: index(for: value), in: scrollView)
        if abs(scrollView.contentOffset.x - targetOffset) > 0.5 {
            context.coordinator.isProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: false)
            context.coordinator.isProgrammaticScroll = false
        }
    }

    private var rulerContent: SparkCustomRulerContent {
        SparkCustomRulerContent(
            range: range,
            step: step,
            majorStride: majorStride,
            tickSpacing: tickSpacing
        )
    }

    private var totalSteps: Int {
        guard step > 0, range.upperBound >= range.lowerBound else { return 0 }
        return Int(((range.upperBound - range.lowerBound) / step).rounded())
    }

    private func index(for value: Double) -> Int {
        guard step > 0 else { return 0 }
        let clampedValue = min(max(value, range.lowerBound), range.upperBound)
        return Int(((clampedValue - range.lowerBound) / step).rounded())
    }

    private func value(for index: Int) -> Double {
        min(max(range.lowerBound + Double(index) * step, range.lowerBound), range.upperBound)
    }

    private func contentInset(for scrollView: UIScrollView) -> UIEdgeInsets {
        let horizontalInset = max((scrollView.bounds.width - tickSpacing) / 2, 0)
        return UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
    }

    private func contentOffset(for index: Int, in scrollView: UIScrollView) -> CGFloat {
        CGFloat(index) * tickSpacing - scrollView.contentInset.left
    }

    private func index(for scrollView: UIScrollView) -> Int {
        let rawIndex = ((scrollView.contentOffset.x + scrollView.contentInset.left) / tickSpacing).rounded()
        return min(max(Int(rawIndex), 0), totalSteps)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: SparkCustomRulerScrollView
        var hostingController: UIHostingController<SparkCustomRulerContent>?
        var isProgrammaticScroll = false
        private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

        init(parent: SparkCustomRulerScrollView) {
            self.parent = parent
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isProgrammaticScroll == false else { return }
            parent.value = parent.value(for: parent.index(for: scrollView))
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            snap(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if decelerate == false {
                snap(scrollView)
            }
        }

        private func snap(_ scrollView: UIScrollView) {
            let index = parent.index(for: scrollView)
            let xOffset = parent.contentOffset(for: index, in: scrollView)
            scrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: false)
            parent.value = parent.value(for: index)

            feedbackGenerator.impactOccurred()
        }
    }
}

private struct SparkCustomRulerContent: View {
    var range: ClosedRange<Double>
    var step: Double
    var majorStride: Double
    var tickSpacing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0...totalSteps, id: \.self) { index in
                let isMajor = isMajorStep(index)

                VStack {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 1, height: isMajor ? 30 : 15)

                    if isMajor {
                        Text(labelText(for: value(for: index)))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: tickSpacing)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 50)
    }

    private var totalSteps: Int {
        guard step > 0, range.upperBound >= range.lowerBound else { return 0 }
        return Int(((range.upperBound - range.lowerBound) / step).rounded())
    }

    private func value(for index: Int) -> Double {
        range.lowerBound + Double(index) * step
    }

    private func isMajorStep(_ index: Int) -> Bool {
        guard step > 0, majorStride > 0 else { return false }
        return index % max(Int((majorStride / step).rounded()), 1) == 0
    }

    private func labelText(for value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
