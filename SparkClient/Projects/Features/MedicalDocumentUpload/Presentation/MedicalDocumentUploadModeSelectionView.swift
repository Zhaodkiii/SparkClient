import SwiftUI

/// 文档类型选择视图
/// 当 AI 无法自动识别文档类型时显示，让用户手动选择类型以继续处理
/// 展示四种类型卡片：病例、体检报告、医疗报告、处方/用药
struct MedicalDocumentUploadModeSelectionView: View {
    var onSelectMode: ((MedicalDocumentKind) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // 提示标题区域
                headerSection
                
                // 类型选择卡片列表
                VStack(spacing: 12) {
                    ModeSelectionCard(
                        kind: .caseDocument,
                        onSelect: { onSelectMode?(.caseDocument) }
                    )
                    
                    ModeSelectionCard(
                        kind: .healthExamReport,
                        onSelect: { onSelectMode?(.healthExamReport) }
                    )
                    
                    ModeSelectionCard(
                        kind: .medicalReport,
                        onSelect: { onSelectMode?(.medicalReport) }
                    )
                    
                    ModeSelectionCard(
                        kind: .prescription,
                        onSelect: { onSelectMode?(.prescription) }
                    )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 标题区域
    
    /// 提示用户无法自动识别，需要手动选择
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color(.systemOrange))
            
            Text(L10n.text("medical.upload.type_selection.title"))
                .font(.headline)
            
            Text(L10n.text("medical.upload.type_selection.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - 类型选择卡片

/// 单个文档类型的选择卡片
/// 包含图标、标题、描述和箭头
private struct ModeSelectionCard: View {
    let kind: MedicalDocumentKind
    let onSelect: () -> Void
    
    /// 根据类型返回对应的系统颜色
    private var accentColor: Color {
        switch kind {
        case .caseDocument:
            return Color(.systemBlue)
        case .healthExamReport:
            return Color(.systemGreen)
        case .medicalReport:
            return Color(.systemOrange)
        case .prescription, .medication:
            return Color(.systemRed)
        case .medicineBox:
            return Color(.systemPurple)
        case .auto:
            return Color(.systemIndigo)
        }
    }
    
    /// 根据类型返回对应的图标
    private var iconName: String {
        switch kind {
        case .caseDocument:
            return "list.clipboard.fill"
        case .healthExamReport:
            return "heart.text.square.fill"
        case .medicalReport:
            return "doc.text.fill"
        case .prescription, .medication:
            return "pills.fill"
        case .medicineBox:
            return "shippingbox.fill"
        case .auto:
            return "wand.and.stars"
        }
    }
    
    /// 根据类型返回对应的本地化标题
    private var title: String {
        switch kind {
        case .caseDocument:
            return L10n.text("medical.upload.type_selection.case")
        case .healthExamReport:
            return L10n.text("medical.upload.type_selection.health_exam")
        case .medicalReport:
            return L10n.text("medical.upload.type_selection.medical_report")
        case .prescription:
            return L10n.text("medical.upload.type_selection.prescription")
        case .medication:
            return L10n.text("medical.upload.type_selection.medication")
        case .medicineBox:
            return L10n.text("home.medical.list.medicine_box.title", fallback: "药品")
        case .auto:
            return L10n.text("medical.upload.kind.auto")
        }
    }
    
    /// 根据类型返回对应的本地化描述
    private var subtitle: String {
        switch kind {
        case .caseDocument:
            return L10n.text("medical.upload.type_selection.case.subtitle")
        case .healthExamReport:
            return L10n.text("medical.upload.type_selection.health_exam.subtitle")
        case .medicalReport:
            return L10n.text("medical.upload.type_selection.medical_report.subtitle")
        case .prescription:
            return L10n.text("medical.upload.type_selection.prescription.subtitle")
        case .medication:
            return L10n.text("medical.upload.type_selection.medication.subtitle")
        case .medicineBox:
            return L10n.text("medical.upload.type_selection.medicine_box.subtitle", fallback: "识别药盒、药瓶、包装或说明书")
        case .auto:
            return L10n.text("medical.upload.kind.auto.subtitle")
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 图标区域
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                }
                
                // 文字信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
