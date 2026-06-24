import SwiftUI

struct MemberModuleToggleRow: View {
    let module: MemberSetupModule
    let selectionStatus: ModuleSelectionStatus
    let onOpen: () -> Void

    enum ModuleSelectionStatus {
        case notOpened
        case selectedIncomplete
        case completed

        init(isSelected: Bool, isCompleted: Bool) {
            if isCompleted {
                self = .completed
            } else if isSelected {
                self = .selectedIncomplete
            } else {
                self = .notOpened
            }
        }

        var statusText: String {
            switch self {
            case .notOpened: return L10n.text("member.module.status.not_opened");
        case .selectedIncomplete: return L10n.text("member.setup.common.incomplete");
        case .completed: return L10n.text("home.members.save.success");            }
        }
    }

    var body: some View {
        
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    moduleIcon
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(module.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            
                            Text(selectionStatus.statusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(statusBackgroundColor)
                                )
                        }
                        
                        Text(module.subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBlue))
                        
                        Text(description)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selectionStatus == .completed ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray2))
                    .frame(width: 36, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(selectionStatus == .selectedIncomplete ? Color(uiColor: .systemGreen) : .clear, lineWidth: 1.5)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)

//        
//        HStack(alignment: .center, spacing: 18) {
//            Button(action: onOpen) {
//                HStack(alignment: .center, spacing: 18) {
//                    moduleIcon
//
//                    VStack(alignment: .leading, spacing: 8) {
//                        HStack(spacing: 8) {
//                            Text(module.title)
//                                .font(.title3.weight(.bold))
//                                .foregroundStyle(.primary)
//
//                            Text(selectionStatus.statusText)
//                                .font(.caption.weight(.semibold))
//                                .foregroundStyle(statusColor)
//                                .padding(.horizontal, 10)
//                                .padding(.vertical, 4)
//                                .background(
//                                    Capsule(style: .continuous)
//                                        .fill(statusBackgroundColor)
//                                )
//                        }
//
//                        Text(module.subtitle)
//                            .font(.subheadline.weight(.semibold))
//                            .foregroundStyle(Color(uiColor: .systemBlue))
//
//                        Text(description)
//                            .font(.subheadline)
//                            .lineSpacing(4)
//                            .foregroundStyle(.secondary)
//                            .fixedSize(horizontal: false, vertical: true)
//                    }
//                }
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .contentShape(Rectangle())
//            }
//            .buttonStyle(.plain)
//
//            Button(action: onOpen) {
//                Image(systemName: "chevron.right")
//                    .font(.title3.weight(.semibold))
//                    .foregroundStyle(selectionStatus == .completed ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray2))
//                    .frame(width: 36, height: 44)
//            }
//            .buttonStyle(.plain)
//        }
//        .padding(.horizontal, 34)
//        .padding(.vertical, 28)
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .background(Color(uiColor: .secondarySystemGroupedBackground))
//        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
//        .overlay {
//            RoundedRectangle(cornerRadius: 24, style: .continuous)
//                .stroke(selectionStatus == .completed ? Color(uiColor: .systemGreen) : .clear, lineWidth: 1.5)
//        }
//        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 8)
    }

    private var statusColor: Color {
        switch selectionStatus {
        case .notOpened: return .secondary
        case .selectedIncomplete: return .orange
        case .completed: return Color(uiColor: .systemGreen)
        }
    }

    private var statusBackgroundColor: Color {
        switch selectionStatus {
        case .notOpened: return Color(uiColor: .tertiarySystemBackground)
        case .selectedIncomplete: return Color.orange.opacity(0.12)
        case .completed: return Color(uiColor: .systemGreen).opacity(0.12)
        }
    }

    private var moduleIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(iconColor)
                .frame(width: 76, height: 76)

            Image(systemName: iconName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var iconName: String {
        switch module {
        case .medical:
            return "heart.fill"
        case .nutrition:
            return "fork.knife"
        case .dailyHealth:
            return "figure.walk"
        }
    }

    private var iconColor: Color {
        switch module {
        case .medical:
            return Color(red: 1.0, green: 0.33, blue: 0.38)
        case .nutrition:
            return Color(red: 0.29, green: 0.79, blue: 0.39)
        case .dailyHealth:
            return Color(uiColor: .systemBlue)
        }
    }

    private var description: String {
        switch module {
        case .medical:
            return L10n.text("member.module.symptom.d0d35c");
        case .nutrition:
            return L10n.text("member.module.nutrition.5ff02b");
        case .dailyHealth:
            return L10n.text("member.module.lifestyle.b94beb");        }
    }
}
