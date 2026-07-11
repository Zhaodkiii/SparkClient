import SwiftUI

/// 病例卡片：视觉结构对齐 HealthClient `MedicalRecordCard`，颜色改用系统近似色。
struct MedicalRecordCard: View {
    let item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    var logger: Logger? = nil
    var onExaminationReportsUpdated: (([SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments]) -> Void)? = nil
    let onUpdated: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void
    let onDeleted: (Int) -> Void
    var maxChips: Int = 8
    
    private var chiefComplaintText: String {
        item.title?.nonEmpty ?? ""
    }
    
    private var diagnosisText: String {
        item.diagnosisSummary?.nonEmpty ?? ""
    }
    
    private var dateText: String {
        let date = item.updatedAt ?? item.createdAt ?? .now
        return Self.dateFormatter.string(from: date)
    }
    
    private var style: SeverityStyle { SeverityStyle(severity: .medium) }
    
    private var recordStatus: CardStatus {
        guard let status = item.status else { return .empty }
        switch status {
        case 0:
            return .pendingDiagnosis
        case 1:
            return .inTreatment
        case 2:
            return .review
        case 3:
            return .chronicManagement
        case 4:
            return .cured
        default:
            return .unknown
        }
    }
    
    private let noteText: String? = nil
    
    private var structuredSymptomNames: [String] {
        (completeData?.symptoms ?? [])
            .filter { $0.medicalCase == item.id }
            .map(\.name)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    var body: some View {
        MainNavigationLink {
            MedicalCaseDetailPage(
                item: item,
                completeData: completeData,
                workflowAPI: workflowAPI,
                fileTransferService: fileTransferService,
                memberContextStore: memberContextStore,
                notificationClient: notificationClient,
                onUpdated: onUpdated,
                onDeleted: onDeleted,
                logger: logger,
                onExaminationReportsUpdated: onExaminationReportsUpdated
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.caption)
                        .foregroundStyle(style.accent)
                    Text(L10n.text("home.medical.list.medical_case.chief_complaint"))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(style.accent)
                    Text(chiefComplaintText)
                        .font(.subheadline)
                        .foregroundStyle(style.textStrong)
                        .lineLimit(2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("home.medical.list.medical_case.diagnosis"))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(style.textSecondary)
                    Text(diagnosisText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(style.textStrong)
                        .lineLimit(2)
                }
                
                if !structuredSymptomNames.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("home.medical.list.medical_case.symptoms"))
                            .font(.subheadline).foregroundStyle(style.textSecondary)
                        MedicalFlowTagView(
                            items: limitedList(structuredSymptomNames, max: maxChips),
                            extraCount: max(0, structuredSymptomNames.count - maxChips),
                            tint: style.chipBG,
                            foreground: style.chipFG,
                            shape: .roundedRectangle(cornerRadius: 8)
                        )
                    }
                }
                
                if let medications = item.medications, !medications.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "pills.fill")
                            Text(L10n.text("home.medical.list.medical_case.medications"))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.textSecondary)
                        
                        MedicalFlowTagView(
                            items: limitedList(medications, max: maxChips),
                            extraCount: max(0, medications.count - maxChips),
                            tint: Color.blue.opacity(0.12),
                            foreground: .blue,
                            shape: .roundedRectangle(cornerRadius: 8)
                        )
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if let noteText {
                        Text(noteText)
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(style.accent)
                    }
                    
                    HStack {
                        StatusPill(text: recordStatus.displayName, tint: statusTint(recordStatus))
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                            Text(dateText)
                        }
                        .font(.footnote)
                        .foregroundStyle(style.textSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(L10n.text("home.medical.list.medical_case.updated_at"))\(dateText)")
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.cardBG)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(style.accent)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style.border, lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .padding(14)

        }
        .buttonStyle(.plain)
    }
    
    private func limitedList(_ items: [String], max: Int) -> [String] {
        Array(items.prefix(max))
    }
    
    private func statusTint(_ status: CardStatus) -> Color {
        switch status {
        case .empty:
            return .clear
        case .chronicManagement:
            return .gray.opacity(0.15)
        case .inTreatment:
            return .blue.opacity(0.15)
        case .review:
            return .teal.opacity(0.15)
        case .cured:
            return .green.opacity(0.15)
        case .pendingDiagnosis:
            return .orange.opacity(0.15)
        case .unknown:
            return .gray.opacity(0.15)
        }
    }
    
    private var accessibilitySummary: String {
        [
            chiefComplaintText,
            diagnosisText,
            recordStatus.displayName,
            dateText
        ].joined(separator: "，")
    }
}

private struct MedicalFlowTagView: View {
    enum Shape {
        case capsule
        case roundedRectangle(cornerRadius: CGFloat)
    }
    
    let items: [String]
    let extraCount: Int
    let tint: Color
    let foreground: Color
    let shape: Shape
    
    var body: some View {
        MedicalFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                tag(item)
            }
            if extraCount > 0 {
                tag("+\(extraCount)")
            }
        }
    }
    
    private func tag(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint)
            .foregroundStyle(foreground)
            .clipShape(shapeView)
    }
    
    private var shapeView: AnyShape {
        switch shape {
        case .capsule:
            return AnyShape(Capsule())
        case .roundedRectangle(let cornerRadius):
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private struct MedicalFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func makeCache(subviews: Subviews) -> FlowCache {
        FlowCache()
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout FlowCache) -> CGSize {
        let maxWidth = proposal.replacingUnspecifiedDimensions().width
        if cache.cachedWidth != maxWidth || cache.cachedResult == nil {
            cache.cachedWidth = maxWidth
            cache.cachedResult = FlowResult(in: maxWidth, subviews: subviews, spacing: spacing)
        }
        return cache.cachedResult!.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout FlowCache) {
        let maxWidth = proposal.replacingUnspecifiedDimensions().width
        if cache.cachedWidth != maxWidth || cache.cachedResult == nil {
            cache.cachedWidth = maxWidth
            cache.cachedResult = FlowResult(in: maxWidth, subviews: subviews, spacing: spacing)
        }
        guard let result = cache.cachedResult else { return }
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.frames[index].minX,
                    y: bounds.minY + result.frames[index].minY
                ),
                proposal: .unspecified
            )
        }
    }
    
    struct FlowCache {
        var cachedWidth: CGFloat = 0
        var cachedResult: FlowResult?
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var frames: [CGRect] = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.frames = frames
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

private struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = shape.path(in:)
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color
    
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(.primary)
    }
}

private enum CardStatus {
    case chronicManagement
    case inTreatment
    case review
    case cured
    case pendingDiagnosis
    case empty
    case unknown
    
    var displayName: String {
        switch self {
        case .empty:
            return ""
        case .chronicManagement:
            return L10n.text("home.medical.list.medical_case.status.chronic_management")
        case .inTreatment:
            return L10n.text("home.medical.list.medical_case.status.in_treatment")
        case .review:
            return L10n.text("home.medical.list.medical_case.status.review")
        case .cured:
            return L10n.text("home.medical.list.medical_case.status.cured")
        case .pendingDiagnosis:
            return L10n.text("home.medical.list.medical_case.status.pending_diagnosis")
        case .unknown:
            return L10n.text("home.medical.list.medical_case.status.unknown")
        }
    }
}

private enum CardSeverity {
    case low
    case medium
    case high
}

private struct SeverityStyle {
    let severity: CardSeverity
    
    var accent: Color {
        switch severity {
        case .low:
            return Color(uiColor: .systemTeal)
        case .medium:
            return Color(uiColor: .systemOrange)
        case .high:
            return Color(uiColor: .systemRed)
        }
    }
    
    var cardBG: Color { accent.opacity(0.06) }
    var border: Color { accent.opacity(0.25) }
    var chipBG: Color { accent.opacity(0.12) }
    var chipFG: Color { accent }
    var textStrong: Color { .primary }
    var textSecondary: Color { .secondary }
}
