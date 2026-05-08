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
    @State private var showDeleteConfirmation = false
    @State private var addMemberMode: AddFamilyMemberView.Mode?
    @State private var showMedicalDocumentUpload = false
    @State private var showTaskCenter = false

    var body: some View {
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
        .sheet(item: $addMemberMode) { mode in
            CompatibleNavigationContainer {
                AddFamilyMemberView(mode: mode, store: viewModel.memberContextStoreForBinding)
            }
        }
        .alert(
            L10n.text("home.members.delete.confirm_title"),
            isPresented: $showDeleteConfirmation,
            presenting: memberActionTarget
        ) { target in
            Button(L10n.text("common.ok"), role: .cancel) {
                memberActionTarget = nil
            }
            Button(L10n.text("home.members.delete"), role: .destructive) {
                Task {
                    await viewModel.deleteMember(target)
                    memberActionTarget = nil
                    triggerNotificationHaptic(.success)
                }
            }
        } message: { target in
            Text(String(format: L10n.text("home.members.delete.confirm_message"), target.name))
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.loadInitialIfNeeded(syncRemote: true)
        }
        .fullScreenCover(isPresented: $showMedicalDocumentUpload) {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedMemberID)
    }

    private var memberSelectorBar: some View {
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
                        onEdit: {
                            addMemberMode = .edit(member)
                            triggerHaptic(style: .light)
                        },
                        onDelete: {
                            memberActionTarget = member
                            showDeleteConfirmation = true
                        }
                    )
                }

                Button {
                    addMemberMode = .create
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
                .accessibilityLabel(L10n.text("home.members.create"))
            }
            .padding(.vertical, 4)
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
                    showMedicalDocumentUpload = true
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
                            onPrescriptionBatchesUpdated: { batches in
                                viewModel.updateMedicalCompleteData { completeData in
                                    completeData.prescriptionBatches = batches
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
        case .medications:
            return L10n.text("home.medical.card.medications.title")
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
        case .medications:
            return L10n.text("home.medical.card.medications.subtitle")
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
        case .medications:
            return .medications
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
    let onEdit: () -> Void
    let onDelete: () -> Void

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
                    Image(systemName: "square.and.pencil")
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
            Button(L10n.text("home.members.edit"), systemImage: "square.and.pencil") {
                onEdit()
            }
            Button(L10n.text("home.members.delete"), systemImage: "trash", role: .destructive) {
                onDelete()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        }
    }
}




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

extension HomeViewModel {
    static var preview: HomeViewModel {
        let now = Date()
        let accountID: Int64 = 1
        let memberA = Member(id: 1, name: "本人", gender: "female", relationship: "self", birthDate: now.addingTimeInterval(-86_400 * 365 * 30), isPrimary: true)
        let memberB = Member(id: 2, name: "妈妈", gender: "female", relationship: "mother", birthDate: now.addingTimeInterval(-86_400 * 365 * 56), isPrimary: false)

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
                HomeDashboard.MedicalCard(id: .medications, count: 8, latestDate: now.addingTimeInterval(-86_400 * 3), symbol: "pills.fill")
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
