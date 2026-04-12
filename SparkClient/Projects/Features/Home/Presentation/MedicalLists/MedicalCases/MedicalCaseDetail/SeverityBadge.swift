import SwiftUI

/// 病例时间轴上的状态/严重度胶囊标签（对齐 HealthClient `SeverityBadge` 视觉结构）。
struct MedicalCaseSeverityBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.15))
                    .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
            )
            .foregroundStyle(tint)
            .accessibilityLabel(text)
    }
}

#Preview("Severity badge — Light") {
    VStack(spacing: 12) {
        MedicalCaseSeverityBadge(text: "治疗中", tint: Color(uiColor: .systemBlue))
        MedicalCaseSeverityBadge(text: "复诊", tint: Color(uiColor: .systemTeal))
    }
    .padding()
    .frame(maxWidth: .infinity)
    .preferredColorScheme(.light)
}

#Preview("Severity badge — Dark") {
    VStack(spacing: 12) {
        MedicalCaseSeverityBadge(text: "治疗中", tint: Color(uiColor: .systemBlue))
        MedicalCaseSeverityBadge(text: "复诊", tint: Color(uiColor: .systemTeal))
    }
    .padding()
    .frame(maxWidth: .infinity)
    .preferredColorScheme(.dark)
}
