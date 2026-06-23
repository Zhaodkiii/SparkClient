import SwiftUI

enum MedicalGuideIntroKind {
    case basicProfile
    case healthHistory
    case lifestyle
    case examArchive

    var illustrationSymbols: [MedicalGuideIllustrationSymbol] {
        switch self {
        case .basicProfile:
            return [
                .init(systemName: "chart.bar.fill", size: 18, tint: .yellow, offsetX: 18, offsetY: -40),
                .init(systemName: "person.crop.circle.fill", size: 34, tint: .blue, offsetX: -28, offsetY: -6),
                .init(systemName: "scalemass.fill", size: 28, tint: .purple, offsetX: 28, offsetY: -4),
                .init(systemName: "briefcase.fill", size: 24, tint: .orange, offsetX: 0, offsetY: 30)
            ]
        case .healthHistory:
            return [
                .init(systemName: "stethoscope", size: 18, tint: .red, offsetX: 20, offsetY: -40),
                .init(systemName: "list.clipboard.fill", size: 31, tint: .blue, offsetX: -28, offsetY: -5),
                .init(systemName: "pills.fill", size: 29, tint: .pink, offsetX: 29, offsetY: -4, rotationDegrees: -12),
                .init(systemName: "dna", size: 24, tint: .teal, offsetX: 0, offsetY: 30)
            ]
        case .lifestyle:
            return [
                .init(systemName: "lungs.fill", size: 18, tint: .green, offsetX: 18, offsetY: -40),
                .init(systemName: "smoke.fill", size: 30, tint: .orange, offsetX: -28, offsetY: -5),
                .init(systemName: "bed.double.fill", size: 28, tint: .indigo, offsetX: 28, offsetY: -4),
                .init(systemName: "wineglass.fill", size: 23, tint: .purple, offsetX: 0, offsetY: 30)
            ]
        case .examArchive:
            return [
                .init(systemName: "doc.text.fill", size: 18, tint: .blue, offsetX: 18, offsetY: -40),
                .init(systemName: "building.2.fill", size: 29, tint: .teal, offsetX: -28, offsetY: -5),
                .init(systemName: "magnifyingglass", size: 25, tint: .indigo, offsetX: 28, offsetY: -4),
                .init(systemName: "chart.line.uptrend.xyaxis", size: 22, tint: .green, offsetX: 0, offsetY: 30)
            ]
        }
    }
}

struct MedicalGuideIntroIllustration: View {
    let kind: MedicalGuideIntroKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color.blue.opacity(0.08),
                            Color.purple.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 142, height: 142)
                .shadow(color: .black.opacity(0.05), radius: 18, y: 10)

            ForEach(kind.illustrationSymbols) { symbol in
                Image(systemName: symbol.systemName)
                    .font(.system(size: symbol.size, weight: symbol.weight))
                    .foregroundStyle(symbol.tint)
                    .symbolRenderingMode(.hierarchical)
                    .rotationEffect(.degrees(symbol.rotationDegrees))
                    .offset(x: symbol.offsetX, y: symbol.offsetY)
                    .shadow(color: symbol.tint.opacity(0.18), radius: 6, y: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.3)
    }
}

struct MedicalGuideIllustrationSymbol: Identifiable {
    let id: String
    let systemName: String
    let size: CGFloat
    let weight: Font.Weight
    let tint: Color
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotationDegrees: Double

    init(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight = .semibold,
        tint: Color,
        offsetX: CGFloat,
        offsetY: CGFloat,
        rotationDegrees: Double = 0
    ) {
        self.id = "\(systemName)-\(offsetX)-\(offsetY)-\(size)"
        self.systemName = systemName
        self.size = size
        self.weight = weight
        self.tint = tint
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotationDegrees = rotationDegrees
    }
}
