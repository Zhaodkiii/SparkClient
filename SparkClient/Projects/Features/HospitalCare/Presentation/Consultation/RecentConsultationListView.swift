import Combine
import SwiftUI

/// 最近问诊列表（线上问诊第二步 Tab）：仅展示患者已提交的线上问诊单。
/// 卡片点击进入问诊详情；卡片内对话图标直接进入关联问诊对话与医生沟通。
struct RecentConsultationListView: View {
    @StateObject private var viewModel: RecentConsultationListViewModel
    @ObservedObject private var memberContextStore: MemberContextStore

    private let onOpenThread: (UUID) -> Void
    private let onOpenDetail: (HospitalConsultationDTO) -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        onOpenThread: @escaping (UUID) -> Void,
        onOpenDetail: @escaping (HospitalConsultationDTO) -> Void
    ) {
        self.memberContextStore = memberContextStore
        self.onOpenThread = onOpenThread
        self.onOpenDetail = onOpenDetail
        _viewModel = StateObject(
            wrappedValue: RecentConsultationListViewModel(
                dependencies: dependencies,
                memberContextStore: memberContextStore
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.consultations.isEmpty {
                ProgressView("正在加载最近问诊…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.consultations.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "stethoscope")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(viewModel.loadError ?? "还没有线上问诊记录")
                        .foregroundStyle(.secondary)
                    Text("选择科室与医生，提交问诊材料后即可发起线上问诊")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    if viewModel.loadError != nil {
                        Button("重试") { Task { await viewModel.reload() } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.consultations) { consultation in
                    ConsultationCardView(
                        consultation: consultation,
                        onTap: { onOpenDetail(consultation) },
                        onOpenChat: { onOpenThread(consultation.threadId) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
                .refreshable { await viewModel.reload() }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task { await viewModel.onAppear() }
        .onChange(of: memberContextStore.context.selectedMemberID) { _ in
            Task { await viewModel.reload() }
        }
    }
}

/// 最近问诊卡片：问诊信息 + 对话快捷入口。
struct ConsultationCardView: View {
    let consultation: HospitalConsultationDTO
    let onTap: () -> Void
    let onOpenChat: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(consultation.doctor?.displayName ?? consultation.agent.name ?? "问诊医生")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let title = consultation.doctor?.title, title.isEmpty == false {
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ConsultationStatusText.label(for: consultation.serviceStatus))
                        .font(.caption)
                        .foregroundStyle(ConsultationStatusText.color(for: consultation.serviceStatus))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ConsultationStatusText.color(for: consultation.serviceStatus).opacity(0.12))
                        .clipShape(Capsule())
                }
                Text([consultation.department?.name, consultation.hospital?.shortName ?? consultation.hospital?.name]
                    .compactMap { $0 }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if consultation.chiefComplaint.isEmpty == false {
                    Text("主诉：\(consultation.chiefComplaint)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Text("问诊编号：\(consultation.consultNo)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let attachments = consultation.attachmentCount, attachments > 0 {
                        Label("附件 \(attachments)", systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let submittedAt = consultation.submittedAt {
                        Text(submittedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button(action: onOpenChat) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color(uiColor: .systemTeal))
                            .padding(8)
                            .background(Color(uiColor: .systemTeal).opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("进入问诊对话")
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 问诊状态文案与颜色（患者视角）。
enum ConsultationStatusText {
    /// 待接诊、问诊中：进入线上问诊页时应落到「最近问诊」。
    static func isInProgress(_ status: String) -> Bool {
        switch status {
        case "pending_doctor", "doctor_joined":
            return true
        default:
            return false
        }
    }

    static func label(for status: String) -> String {
        switch status {
        case "pending_doctor": return "待接诊"
        case "doctor_joined": return "问诊中"
        case "ai_active": return "AI 接待中"
        case "ended": return "已结束"
        default: return status
        }
    }

    static func color(for status: String) -> Color {
        switch status {
        case "pending_doctor": return Color(uiColor: .systemOrange)
        case "doctor_joined": return Color(uiColor: .systemTeal)
        case "ai_active": return Color(uiColor: .systemIndigo)
        case "ended": return .secondary
        default: return .secondary
        }
    }
}

@MainActor
final class RecentConsultationListViewModel: ObservableObject {
    @Published private(set) var consultations: [HospitalConsultationDTO] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let dependencies: HospitalCareFeatureDependencies
    private let memberContextStore: MemberContextStore
    private var hasLoadedOnce = false

    init(dependencies: HospitalCareFeatureDependencies, memberContextStore: MemberContextStore) {
        self.dependencies = dependencies
        self.memberContextStore = memberContextStore
    }

    func onAppear() async {
        guard hasLoadedOnce == false else { return }
        hasLoadedOnce = true
        await reload()
    }

    func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            consultations = try await dependencies.loadConsultations.execute(
                memberID: memberContextStore.context.selectedMemberID
            )
        } catch {
            loadError = "最近问诊加载失败，请稍后重试"
        }
    }
}
