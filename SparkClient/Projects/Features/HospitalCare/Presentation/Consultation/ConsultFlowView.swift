import SwiftUI

/// 线上问诊流程入口页（科室选择页）：
/// 选择科室后通过 routeStore push 到独立的医生选择页面；
/// 选择医生后再 push 到问诊材料填写页面，完全使用全局导航栈。
struct ConsultFlowView: View {
    @State private var hospital: HospitalSummary?
    @State private var landingFocus: HospitalConsultationFocus?
    @State private var loadFailed = false
    @State private var detailConsultation: HospitalConsultationDTO?

    private let dependencies: HospitalCareFeatureDependencies
    private let memberContextStore: MemberContextStore
    private let sessionStore: AppSessionStore
    private let routeStore: AppRouteStore
    private let focus: HospitalConsultationFocus
    private let onOpenThread: (UUID) -> Void

    init(
        dependencies: HospitalCareFeatureDependencies,
        memberContextStore: MemberContextStore,
        sessionStore: AppSessionStore,
        routeStore: AppRouteStore,
        focus: HospitalConsultationFocus = .departments,
        onOpenThread: @escaping (UUID) -> Void
    ) {
        self.dependencies = dependencies
        self.memberContextStore = memberContextStore
        self.sessionStore = sessionStore
        self.routeStore = routeStore
        self.focus = focus
        self.onOpenThread = onOpenThread
    }

    var body: some View {
        Group {
            if let hospital, let landingFocus {
                ConsultDepartmentSelectView(
                    dependencies: dependencies,
                    hospital: hospital,
                    memberContextStore: memberContextStore,
                    sessionStore: sessionStore,
                    routeStore: routeStore,
                    initialTab: landingFocus == .recent ? .recent : .departments,
                    onOpenThread: onOpenThread,
                    onOpenDetail: { detailConsultation = $0 }
                )
            } else if loadFailed {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cross.case")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("医院服务暂不可用")
                        .font(.headline)
                    Button("重试") { Task { await resolveEntry() } }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("正在加载医院信息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("线上问诊")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolveEntry() }
        .sheet(item: $detailConsultation) { consultation in
            NavigationStack {
                ConsultationDetailView(
                    consultation: consultation,
                    onOpenThread: { threadID in
                        detailConsultation = nil
                        onOpenThread(threadID)
                    }
                )
                .navigationTitle("问诊详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { detailConsultation = nil }
                    }
                }
            }
        }
    }

    private func resolveEntry() async {
        guard case .signedIn(let session) = sessionStore.state else {
            loadFailed = true
            return
        }
        loadFailed = false
        landingFocus = nil
        hospital = nil
        async let hospitalResolution = dependencies.resolveDemoHospital.execute(accountID: session.accountID)
        async let consultations = loadConsultationsForLanding()
        let resolution = await hospitalResolution
        let items = await consultations
        switch resolution {
        case .resolved(let resolved):
            landingFocus = ConsultLandingFocus.resolve(requested: focus, consultations: items)
            hospital = resolved
        case .missing, .failed:
            loadFailed = true
        }
    }

    private func loadConsultationsForLanding() async -> [HospitalConsultationDTO] {
        guard focus != .recent else { return [] }
        return (try? await dependencies.loadConsultations.execute(
            memberID: memberContextStore.context.selectedMemberID
        )) ?? []
    }
}

/// 线上问诊入口 Tab：提交后强制最近问诊；医院入口在有进行中问诊时也落到最近问诊。
enum ConsultLandingFocus {
    static func resolve(
        requested: HospitalConsultationFocus,
        consultations: [HospitalConsultationDTO]
    ) -> HospitalConsultationFocus {
        if requested == .recent { return .recent }
        if consultations.contains(where: { ConsultationStatusText.isInProgress($0.serviceStatus) }) {
            return .recent
        }
        return .departments
    }
}

extension HospitalConsultationDTO: Identifiable {
    var id: UUID { consultationId }
}
