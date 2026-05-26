import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    let dependencies: HomeFeatureDependencies
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let session: UserSession

    @State private var hasLoaded = false
    @State private var memberActionTarget: Member?
    @State private var showTaskCenter = false
    @State private var addMemberNearbyTransport = NearbyShareTransport()

    var body: some View {
        homeContent
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                medicalInfoSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        
        
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            memberSelectorBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial)
        }
        .sheet(item: $viewModel.addMemberSheet) { sheet in
            CompatibleNavigationContainer {
                switch sheet {
                case .create(let pendingTicket):
                    AddFamilyMemberView(
                        mode: .create,
                        store: viewModel.memberContextStoreForBinding,
                        shareUseCase: dependencies.shareMemberUseCase,
                        inviteUseCase: dependencies.memberInviteUseCase,
                        nearbyTransport: addMemberNearbyTransport,
                        initialPendingTicket: pendingTicket,
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        }
                    )
                case .edit(let member):
                    AddFamilyMemberView(mode: .edit(member), store: viewModel.memberContextStoreForBinding)
                case .acceptInvite(let inviteID, let preview):
                    AddFamilyMemberView(
                        mode: .acceptInvite(inviteID: inviteID, preview: preview),
                        store: viewModel.memberContextStoreForBinding,
                        inviteUseCase: dependencies.memberInviteUseCase,
                        onBindingAccepted: {
                            Task {
                                await viewModel.refresh()
                                await viewModel.fetchPendingInvitesIfNeeded()
                            }
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.showPendingInvites) {
            PendingMemberInvitesView(
                items: viewModel.pendingInvites,
                highlightInviteID: viewModel.highlightInviteID,
                onAccept: { item in
                    viewModel.openInviteAccept(item)
                },
                onReject: { item in
                    await viewModel.rejectPendingInvite(item)
                },
                onAppearRefresh: {
                    await viewModel.fetchPendingInvitesIfNeeded()
                }
            )
        }
        .sheet(isPresented: memberDetailPresented) {
            if let memberID = viewModel.memberDetailID {
                CompatibleNavigationContainer {
                    MemberDetailView(
                        memberID: memberID,
                        bindingUseCase: dependencies.manageMemberBindingUseCase,
                        memberContextStore: viewModel.memberContextStoreForBinding,
                        memberAPI: dependencies.medicalMemberAPI,
                        shareUseCase: dependencies.shareMemberUseCase,
                        onShare: {
                            if let member = viewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                                viewModel.memberDetailID = nil
                                viewModel.shareMember = member
                            }
                        },
                        onEdit: {
                            if let member = viewModel.dashboard?.members.first(where: { $0.id == memberID }) {
                                viewModel.memberDetailID = nil
                                viewModel.addMemberSheet = .edit(member)
                            }
                        },
                        onDeleted: {
                            viewModel.memberDetailID = nil
                            Task { await viewModel.refresh() }
                        }
                    )
                }
            }
        }
        .sheet(item: $viewModel.shareMember) { member in
            ShareSheet(
                member: member,
                shareUseCase: dependencies.shareMemberUseCase,
                inviteUseCase: dependencies.memberInviteUseCase
            )
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            viewModel.consumePendingShareTicketIfNeeded()
            viewModel.consumePendingInviteIfNeeded()
            await viewModel.loadInitialIfNeeded(syncRemote: true)
        }
        .onReceive(dependencies.routeStore.$routeStacks) { _ in
            // Triggered when AppRouteStore updates (including .memberInvite signal from push/deeplink tap).
            if let stack = dependencies.routeStore.routeStacks[.home],
               let last = stack.last, case .memberInvite(let id) = last {
                viewModel.handleRoute(.memberInvite(inviteID: id))
                // Clear so next same inviteID still triggers; replaceStack was already done.
                dependencies.routeStore.replaceStack([], for: .home)
            }
        }
        .fullScreenCover(isPresented: $medicalDocumentUploadViewModel.isUploadPresented) {
            CompatibleNavigationContainer {
                MedicalDocumentUploadHostView(viewModel: medicalDocumentUploadViewModel)
            }
        }
        .sheet(isPresented: $showTaskCenter) {
            CompatibleNavigationContainer {
                TaskCenterViewController(
                    memberID: viewModel.selectedMemberID,
                    taskManager: dependencies.taskManager
                )
            }
        }
        .onChange(of: medicalDocumentUploadViewModel.saveSucceededRevision) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedMemberID)
    }

    private var memberSelectorBar: some View {
        HStack(spacing: 8) {
            if viewModel.pendingInviteCount > 0 {
                Button {
                    viewModel.showPendingInvites = true
                    triggerHaptic(style: .light)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.badge")
                            .font(.title3)
                        Text("\(viewModel.pendingInviteCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 8, y: -8)
                    }
                    .frame(width: 40, height: 40)
                }
                .accessibilityLabel(
                    String(
                        format: L10n.text("home.members.invite.pending_count"),
                        viewModel.pendingInviteCount
                    )
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.dashboard?.members ?? []) { member in
                    MemberSelectorChip(
                        member: member,
                        badgeText: memberBadgeText(for: member),
                        isSelected: member.id == viewModel.selectedMemberID,
                        onSelect: {
                            viewModel.selectMember(member.id)
                            triggerHaptic(style: .light)
                        },
                        onViewDetail: {
                            viewModel.memberDetailID = member.id
                            triggerHaptic(style: .light)
                        },
                        onShare: {
                            viewModel.shareMember = member
                            triggerHaptic(style: .light)
                        }
                    )
                }

                Button {
                    viewModel.addMemberSheet = .create()
                    triggerHaptic(style: .medium)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("home.members.add.title"))
            }
            .padding(.vertical, 4)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(L10n.homeGreeting(session.displayName))
                    .font(.title.weight(.bold))
                Spacer()
                Button {
                    showTaskCenter = true
                    triggerHaptic(style: .light)
                } label: {
                    Label(
                        NSLocalizedString("task.center.entry", comment: "任务中心"),
                        systemImage: "checklist"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            Text(L10n.text("home.mode.remote"))
                .font(.callout)
                .foregroundStyle(.secondary)

            Label(
                session.signedInAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var medicalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.medical.title"), systemImage: "cross.case")
                    .font(.headline)
                Spacer()
                Button {
                    medicalDocumentUploadViewModel.presentUploadPage()
                    triggerHaptic(style: .medium)
                } label: {
                    Label(L10n.text("home.medical.upload"), systemImage: "sparkles.rectangle.stack")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                if viewModel.dashboard?.selectedMember != nil {
                    Text(viewModel.dashboard?.selectedMember?.name ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            let cards = viewModel.dashboard?.medical.cards ?? []
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(cards, id: \.id) { card in
                    NavigationLink {
                        HomeMedicalListView(
                            route: medicalRoute(for: card.id),
                            completeData: viewModel.dashboard?.medical.completeData,
                            dependencies: dependencies,
                            onMedicalCasesUpdated: { cases in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.medicalCases = cases
                                }
                            },
                            onHealthExamReportsUpdated: { reports in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.healthExamReports = reports
                                }
                            },
                            onExaminationReportsUpdated: { reports in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.examinationReports = reports
                                }
                            },
                            onMedicationPlansUpdated: { plans in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.medicationPlans = plans
                                }
                            },
                            onPrescriptionsUpdated: { prescriptions in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.prescriptions = prescriptions
                                }
                            },
                            onMedicineBoxesUpdated: { boxes in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.medicineBoxes = boxes
                                }
                            }
                        )
                        .hidesMainTabBarWhenPushed()
                    } label: {
                        medicalCard(card)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            viewModel.logMedicalListNavigation(kind: card.id)
                            triggerHaptic(style: .light)
                        }
                    )
                }
            }
        }
    }

    private func medicalCard(_ card: HomeDashboard.MedicalCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: card.symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))

            Text(medicalCardTitle(for: card.id))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(medicalCardSubtitle(for: card.id))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Text("\(card.count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Spacer()
                if let latestDate = card.latestDate {
                    Text(latestDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var memberDetailPresented: Binding<Bool> {
        Binding(
            get: { viewModel.memberDetailID != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.memberDetailID = nil
                }
            }
        )
    }

    private func memberBadgeText(for member: Member) -> String {
        let display = MemberRelationshipCatalog.displayTitle(for: member.relationship)
        guard let first = display.first else { return "·" }
        return String(first)
    }

    private func medicalCardTitle(for kind: HomeDashboard.MedicalCard.Kind) -> String {
        switch kind {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.title")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.title")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.title")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.title", fallback: "服药计划")
        }
    }

    private func medicalCardSubtitle(for kind: HomeDashboard.MedicalCard.Kind) -> String {
        switch kind {
        case .medicalCases:
            return L10n.text("home.medical.card.medical_cases.subtitle")
        case .healthExamReports:
            return L10n.text("home.medical.card.examination_reports.subtitle")
        case .medicalReports:
            return L10n.text("home.medical.card.medical_reports.subtitle")
        case .medicationPlans:
            return L10n.text("home.medical.card.medication_plans.subtitle", fallback: "执行中的规则")
        }
    }

    private func medicalRoute(for kind: HomeDashboard.MedicalCard.Kind) -> HomeMedicalListRoute {
        switch kind {
        case .medicalCases:
            return .medicalCases
        case .healthExamReports:
            return .healthExamReports
        case .medicalReports:
            return .examinationReports
        case .medicationPlans:
            return .medicationPlans
        }
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }

    private func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(type)
#endif
    }
}

/// Member chip with a per-instance action menu (matches Health member button + `confirmationDialog` pattern).
private struct MemberSelectorChip: View {
    let member: Member
    let badgeText: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onViewDetail: () -> Void
    let onShare: () -> Void

    @State private var showActionMenu = false

    var body: some View {
        Button {
            if isSelected {
                showActionMenu = true
            } else {
                onSelect()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor.opacity(isSelected ? 0.25 : 0.14))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(badgeText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? Color.accentColor.opacity(0.95) : .accentColor)
                    }

                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

                if isSelected {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? Color.clear
                        : Color(uiColor: .quaternaryLabel).opacity(0.24),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.04), radius: isSelected ? 4 : 2, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .confirmationDialog(L10n.text("home.members.action_title"), isPresented: $showActionMenu, titleVisibility: .visible) {
            Button(L10n.text("home.members.action.view_detail"), systemImage: "person.text.rectangle") {
                onViewDetail()
            }
            if member.effectiveBinding.canShare {
                Button(L10n.text("home.members.action.share"), systemImage: "square.and.arrow.up") {
                    onShare()
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        }
    }
}



#if DEBUG
#Preview("Light") {
    CompatibleNavigationContainer {
        HomeView(
            dependencies: .preview,
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            session: UserSession(
                accountID: 1,
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now,
                signInMethod: .apple
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    CompatibleNavigationContainer {
        HomeView(
            dependencies: .preview,
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            session: UserSession(
                accountID: 1,
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now,
                signInMethod: .apple
            )
        )
    }
    .preferredColorScheme(.dark)
}
#endif

#if DEBUG
extension HomeViewModel {
    static var preview: HomeViewModel {
        let now = Date()
        let accountID: Int64 = 1
        let memberA = Member(
            id: 1,
            name: "本人",
            gender: "female",
            relationship: "self",
            birthDate: now.addingTimeInterval(-86_400 * 365 * 30),
            isPrimary: true,
            binding: .ownerLike(bindingID: 1)
        )
        let memberB = Member(
            id: 2,
            name: "妈妈",
            gender: "female",
            relationship: "mother",
            birthDate: now.addingTimeInterval(-86_400 * 365 * 56),
            isPrimary: false,
            binding: .ownerLike(bindingID: 2)
        )

        let dashboard = HomeDashboard(
            profile: UserProfile(
                id: accountID,
                email: "preview@spark.com",
                displayName: "Spark User",
                createdAt: now.addingTimeInterval(-86_400 * 120),
                lastSignedInAt: now
            ),
            members: [memberA, memberB],
            selectedMemberID: memberA.id,
            medical: HomeMedicalOverview(cards: [
                HomeDashboard.MedicalCard(id: .medicalCases, count: 4, latestDate: now.addingTimeInterval(-86_400), symbol: "doc.text.fill"),
                HomeDashboard.MedicalCard(id: .healthExamReports, count: 2, latestDate: now.addingTimeInterval(-172_800), symbol: "heart.text.square.fill"),
                HomeDashboard.MedicalCard(id: .medicalReports, count: 6, latestDate: now.addingTimeInterval(-259_200), symbol: "list.clipboard.fill"),
                HomeDashboard.MedicalCard(id: .medicationPlans, count: 3, latestDate: now.addingTimeInterval(-86_400 * 2), symbol: "calendar.badge.clock")
            ], completeData: nil)
        )

        let sessionStore = AppSessionStore(
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: PreviewAuthRepository())
        )
        sessionStore.setAuthenticated(
            UserSession(
                accountID: accountID,
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: now,
                signInMethod: .apple
            )
        )

        let previewPersistence = UserDefaultsSelectedMemberIDStore(
            defaults: UserDefaults(suiteName: "SparkClient.Preview.MemberContext") ?? .standard
        )

        let previewLogger = ConsoleLogger()
        let previewBackend = Backend(baseURL: URL(string: "。.local")!, logger: previewLogger)
        let memberContextStore = MemberContextStore(persistence: previewPersistence)
        memberContextStore.configure(manage: ManageHomeMemberUseCase(memberAPI: previewBackend.medicalMembers))

        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase(
                userProfileRepository: PreviewUserProfileRepository(profile: dashboard.profile),
                medicalQueryAPI: SparkMedicalQueryAPI(configuration: previewBackend.configuration),
                selectedMemberIDPersistence: previewPersistence,
                logger: previewLogger
            ),
            memberContextStore: memberContextStore,
            shareMemberUseCase: ShareMemberUseCase(memberAPI: previewBackend.medicalMembers),
            memberInviteUseCase: MemberInviteUseCase(memberAPI: previewBackend.medicalMembers),
            manageMemberBindingUseCase: ManageMemberBindingUseCase(memberAPI: previewBackend.medicalMembers),
            notificationClient: PreviewNotificationClient(),
            logger: previewLogger
        )

        viewModel.injectPreviewDashboard(dashboard)
        return viewModel
    }
}

@MainActor
private final class PreviewNotificationClient: NotificationClient {
    func publish(_ intent: NotificationIntent) {}
    func success(_ message: String, title: String?, source: String) {}
    func error(_ message: String, title: String?, source: String) {}
    func warning(_ message: String, title: String?, source: String) {}
    func info(_ message: String, title: String?, source: String) {}
}

private struct PreviewUserProfileRepository: UserProfileRepository {
    let profile: UserProfile

    func fetchProfile(id: Int64) async throws -> UserProfile? {
        profile
    }

    func fetchLastActiveProfile() async throws -> UserProfile? {
        profile
    }

    func upsertProfile(
        accountID: Int64,
        email: String,
        displayName: String,
        signedInAt: Date,
        signInMethod: UserSession.SignInMethod
    ) async throws -> UserProfile {
        UserProfile(
            id: accountID,
            email: email,
            displayName: displayName,
            createdAt: profile.createdAt,
            lastSignedInAt: signedInAt
        )
    }
}

private struct PreviewAuthRepository: AuthRepository {
    func restoreSession() async -> UserSession? { nil }

    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession {
        throw NSError(domain: "PreviewAuthRepository", code: -1)
    }

    func requestPhoneOTP(phoneNumber: String) async throws -> PhoneOTPRequestContext {
        PhoneOTPRequestContext(otpID: "preview-otp-id", expiresIn: 300)
    }

    func signInWithPhoneOTP(phoneNumber: String, verificationCode: String, otpID: String) async throws -> UserSession {
        throw NSError(domain: "PreviewAuthRepository", code: -1)
    }

    func signOut() async throws {}
}
#endif
