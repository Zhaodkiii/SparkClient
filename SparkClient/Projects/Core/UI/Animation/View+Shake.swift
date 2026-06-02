import SwiftUI

private struct ShakeGeometryEffect: GeometryEffect {
    var amount: CGFloat = 10
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * 2), y: 0)
        )
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int

    @State private var shakeAmount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeGeometryEffect(amount: 10, animatableData: shakeAmount))
            .onChange(of: trigger) { newValue in
                guard newValue > 0 else { return }
                withAnimation(.linear(duration: 0.45)) {
                    shakeAmount = 3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    shakeAmount = 0
                }
            }
    }
}

extension View {
    /// Horizontal shake when `trigger` increments (e.g. validation failure).
    func shakeOnTrigger(_ trigger: Int) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}
