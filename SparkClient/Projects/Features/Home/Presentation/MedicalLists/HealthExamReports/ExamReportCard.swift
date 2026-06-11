import SwiftUI

/// 体检报告卡片：结构参考 HealthClient `ExamReportCard`，仅使用当前摘要字段做界面展示。
struct ExamReportCard: View {
    let item: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments
    var isLoadingDetails = false
    let fileTransferService: FileTransferService
    let memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let notificationClient: any NotificationClient
    var onDeleted: ((Int) -> Void)?

    @State private var isOtherRiskExpanded = false
    @State private var isShowingAttachments = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var dateText: String {
        guard let examDate = item.examDate else { return "" }
        return Self.dateFormatter.string(from: examDate)
    }

    private var detailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        item.medExamDetails ?? []
    }

    private var attachments: [SparkMedicalSyncAPI.RemoteManagedFile] {
        item.attachments ?? []
    }

    private var abnormalDetailItems: [SparkMedicalSyncAPI.RemoteMedExamDetail] {
        detailItems.filter { $0.flag.isPotentiallyAbnormal }
    }

    /// 高风险：优先展示明显异常项。
    private var highRiskItems: [HealthExamRiskItem] {
        abnormalDetailItems.map {
            HealthExamRiskItem(
                title: $0.itemName,
                category: [$0.category, $0.subCategory].filter { $0.isEmpty == false }.joined(separator: " · "),
                result: [$0.resultValue ?? "", $0.unit].filter { $0.isEmpty == false }.joined(),
                recommendation: $0.diagnosis?.nonEmpty,
                severity: .high
            )
        }
    }

    /// 有体检综述时，作为“其他风险/关注项”展示，避免凭空补业务数据。
    private var otherRiskItems: [HealthExamRiskItem] {
        let detailRows = detailItems
            .filter { $0.flag.isPotentiallyAbnormal == false }
            .prefix(6)
            .map {
                HealthExamRiskItem(
                    title: $0.itemName,
                    category: [$0.category, $0.subCategory].filter { $0.isEmpty == false }.joined(separator: " · "),
                    result: [$0.resultValue ?? "", $0.unit].filter { $0.isEmpty == false }.joined(),
                    recommendation: $0.diagnosis?.nonEmpty,
                    severity: .low
                )
            }

        if detailRows.isEmpty == false {
            return Array(detailRows)
        }

        guard let summary = item.summary?.nonEmpty else { return [] }
        return [
            HealthExamRiskItem(
                title: item.institutionName?.nonEmpty ?? "",
                category: item.reportNo?.nonEmpty ?? "",
                result: summary,
                recommendation: nil,
                severity: .medium
            )
        ]
    }

    private var canNavigateToDetail: Bool {
        detailItems.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                headerSection
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .overlay(alignment: .bottom) {
                        Divider()
                            .background(Color(uiColor: .separator).opacity(0.35))
                    }

                statsSection
                    .padding(16)
            }

            if isLoadingDetails {
                loadingSection
            }

            if highRiskItems.isEmpty == false {
                highRiskSection
            }

            if otherRiskItems.isEmpty == false {
                otherRiskSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemBackground).opacity(0.72))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOtherRiskExpanded)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                    if dateText.isEmpty == false {
                        Image(systemName: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .systemBlue))

                        Text(dateText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }

                    Text(L10n.text("home.medical.list.health_exam.badge"))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 10) {
                    detailAction

                    MedicalAttachmentIconView(
                        count: attachments.count,
                        isExpanded: isShowingAttachments
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isShowingAttachments.toggle()
                        }
                    }
                }
            }

            if let institutionName = item.institutionName?.nonEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(institutionName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if isShowingAttachments && attachments.isEmpty == false {
                MedicalAttachmentListView(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var detailAction: some View {
        if isLoadingDetails {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text("home.medical.list.health_exam.view_detail"))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
        } else if canNavigateToDetail {
            MainNavigationLink {
                HealthExamRecognitionResultView(
                    item: item,
                    fileTransferService: fileTransferService,
                    memberContextStore: memberContextStore,
                    workflowAPI: workflowAPI,
                    notificationClient: notificationClient,
                    onDeleted: onDeleted
                )
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.text("home.medical.list.health_exam.view_detail"))
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 4) {
                Text(L10n.text("home.medical.list.health_exam.view_detail"))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .opacity(0.5)
        }
    }

    private var statsSection: some View {
        HStack(spacing: 8) {
            ExamStatCard(
                value: "\(detailItems.count)",
                label: L10n.text("home.medical.list.health_exam.stats.items"),
                backgroundColor: Color(uiColor: .systemBlue).opacity(0.08),
                textColor: Color(uiColor: .systemBlue)
            )

            ExamStatCard(
                value: "\(max(detailItems.count - abnormalDetailItems.count, 0))",
                label: L10n.text("common.normal"),
                backgroundColor: Color(uiColor: .systemGreen).opacity(0.08),
                textColor: Color(uiColor: .systemGreen)
            )

            ExamStatCard(
                value: "\(abnormalDetailItems.count)",
                label: L10n.text("home.medical.list.health_exam.stats.abnormal"),
                backgroundColor: Color(uiColor: .systemRed).opacity(0.08),
                textColor: Color(uiColor: .systemRed)
            )
        }
    }

    private var loadingSection: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.text("home.medical.list.details.loading"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.65))
    }

    private var highRiskSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(Color(uiColor: .systemRed))

                Text(L10n.text("home.medical.list.health_exam.high_risk.title"))
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .systemRed))

                Spacer()

                Text("\(highRiskItems.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .systemRed), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(uiColor: .systemRed).opacity(0.05))
            .overlay(alignment: .bottom) {
                Divider()
                    .background(Color(uiColor: .systemRed).opacity(0.1))
            }

            VStack(spacing: 8) {
                ForEach(highRiskItems) { item in
                    HealthExamRiskItemCard(item: item, severity: .high)
                }
            }
            .padding(12)
        }
        .background(Color(uiColor: .systemRed).opacity(0.05))
        .overlay(alignment: .top) {
            Divider()
                .background(Color(uiColor: .systemRed).opacity(0.1))
        }
    }

    private var otherRiskSection: some View {
        VStack(spacing: 0) {
            Button {
                isOtherRiskExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .systemOrange))

                    Text(L10n.text("home.medical.list.health_exam.other_risk.title"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text("\(otherRiskItems.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer()

                    Image(systemName: isOtherRiskExpanded ? "chevron.up" : "chevron.down")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.05))
            .overlay(alignment: .bottom) {
                Divider()
                    .background(Color(uiColor: .separator).opacity(0.35))
            }

            if isOtherRiskExpanded {
                VStack(spacing: 8) {
                    ForEach(otherRiskItems) { item in
                        HealthExamRiskItemCard(item: item, severity: item.severity)
                    }
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .overlay(alignment: .top) {
            Divider()
                .background(Color(uiColor: .separator).opacity(0.35))
        }
    }
}

private struct ExamStatCard: View {
    let value: String
    let label: String
    let backgroundColor: Color
    let textColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HealthExamRiskItem: Identifiable {
    let id = UUID()
    let title: String
    let category: String
    let result: String
    let recommendation: String?
    let severity: HealthExamRiskSeverity
}

private enum HealthExamRiskSeverity {
    case high
    case medium
    case low
    case none
}

private struct HealthExamRiskItemCard: View {
    let item: HealthExamRiskItem
    let severity: HealthExamRiskSeverity

    private var theme: HealthExamRiskTheme {
        switch severity {
        case .high:
            return HealthExamRiskTheme(
                backgroundColor: Color(uiColor: .systemRed).opacity(0.1),
                borderColor: Color(uiColor: .systemRed).opacity(0.2),
                textColor: Color(uiColor: .systemRed),
                badgeColor: Color(uiColor: .systemRed),
                badgeText: L10n.text("home.medical.list.health_exam.risk.high")
            )
        case .medium:
            return HealthExamRiskTheme(
                backgroundColor: Color(uiColor: .systemOrange).opacity(0.1),
                borderColor: Color(uiColor: .systemOrange).opacity(0.2),
                textColor: Color(uiColor: .systemOrange),
                badgeColor: Color(uiColor: .systemOrange),
                badgeText: L10n.text("home.medical.list.health_exam.risk.medium")
            )
        case .low:
            return HealthExamRiskTheme(
                backgroundColor: Color(uiColor: .systemYellow).opacity(0.1),
                borderColor: Color(uiColor: .systemYellow).opacity(0.2),
                textColor: Color(uiColor: .systemYellow),
                badgeColor: Color(uiColor: .systemYellow),
                badgeText: L10n.text("home.medical.list.health_exam.risk.low")
            )
        case .none:
            return HealthExamRiskTheme(
                backgroundColor: Color(uiColor: .systemGray5),
                borderColor: Color(uiColor: .systemGray4),
                textColor: .secondary,
                badgeColor: Color(uiColor: .systemGray),
                badgeText: L10n.text("home.medical.list.health_exam.risk.none")
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textColor)

                    if item.category.isEmpty == false {
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(theme.badgeText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.badgeColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if item.result.isEmpty == false {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L10n.text("home.medical.list.health_exam.risk.result"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.result)
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor)
                }
            }

            if let recommendation = item.recommendation, recommendation.isEmpty == false {
                Divider()
                    .background(theme.borderColor)
                    .padding(.vertical, 4)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L10n.text("home.medical.list.health_exam.risk.recommendation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(recommendation)
                        .font(.caption)
                        .foregroundStyle(theme.textColor)
                }
            }
        }
        .padding(12)
        .background(theme.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HealthExamRiskTheme {
    let backgroundColor: Color
    let borderColor: Color
    let textColor: Color
    let badgeColor: Color
    let badgeText: String
}
