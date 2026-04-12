import SwiftUI

/// 病例详情时间轴条目类型：与 HealthClient `TimelineShellPalette` 的色系与图标语义对齐。
enum MedicalCaseTimelineKind: Hashable, Sendable {
    case symptom
    case medication
    case prescription
    case meta

    var palette: MedicalCaseTimelinePalette {
        switch self {
        case .symptom:
            MedicalCaseTimelinePalette(
                tint: Color(uiColor: .systemOrange),
                border: Color(uiColor: .systemOrange).opacity(0.35),
                iconName: "exclamationmark.triangle.fill"
            )
        case .medication:
            MedicalCaseTimelinePalette(
                tint: Color(uiColor: .systemIndigo),
                border: Color(uiColor: .systemIndigo).opacity(0.35),
                iconName: "pills.fill"
            )
        case .prescription:
            MedicalCaseTimelinePalette(
                tint: Color(uiColor: .systemPurple),
                border: Color(uiColor: .systemPurple).opacity(0.35),
                iconName: "doc.text.fill"
            )
        case .meta:
            MedicalCaseTimelinePalette(
                tint: Color(uiColor: .systemGray),
                border: Color(uiColor: .systemGray).opacity(0.35),
                iconName: "cross.case.fill"
            )
        }
    }
}

struct MedicalCaseTimelinePalette: Sendable {
    let tint: Color
    let border: Color
    let iconName: String
}

#Preview("Timeline palette — Light") {
    HStack(spacing: 16) {
        ForEach([MedicalCaseTimelineKind.symptom, .medication, .prescription, .meta], id: \.self) { kind in
            let p = kind.palette
            VStack(spacing: 8) {
                Image(systemName: p.iconName)
                    .font(.title2)
                    .foregroundStyle(p.tint)
                Circle()
                    .fill(p.tint)
                    .frame(width: 36, height: 36)
            }
        }
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Timeline palette — Dark") {
    HStack(spacing: 16) {
        ForEach([MedicalCaseTimelineKind.symptom, .medication, .prescription, .meta], id: \.self) { kind in
            let p = kind.palette
            VStack(spacing: 8) {
                Image(systemName: p.iconName)
                    .font(.title2)
                    .foregroundStyle(p.tint)
                Circle()
                    .fill(p.tint)
                    .frame(width: 36, height: 36)
            }
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
