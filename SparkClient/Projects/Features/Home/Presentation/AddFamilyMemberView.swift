//
//  AddFamilyMemberView.swift
//  SparkClient
//

import SwiftUI

struct AddFamilyMemberView: View {
    enum Mode: Identifiable {
        case create
        case edit(Member)
        case bind(ticket: String, resolved: SparkMedicalMemberAPI.ShareResolveResponse)
        case acceptInvite(inviteID: Int, preview: SparkMedicalMemberAPI.PendingInviteItem)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let member):
                return "edit-\(member.id)"
            case .bind(let ticket, _):
                return "bind-\(ticket.hashValue)"
            case .acceptInvite(let inviteID, _):
                return "accept-\(inviteID)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: MemberContextStore
    let shareUseCase: ShareMemberUseCase?
    let inviteUseCase: MemberInviteUseCase?
    let nearbyTransport: NearbyShareTransport?
    let initialPendingTicket: String?
    let onBindingAccepted: (() -> Void)?
    let onCreatedMemberCompleted: ((Member) -> Void)?
    let homeDependencies: HomeFeatureDependencies?

    @StateObject private var bindViewModel: AddFamilyMemberViewModel

    @State private var name: String
    @State private var relationshipCode: String
    @State private var gender: String
    @State private var birthDate: Date?
    @State private var isSaving = false
    @State private var showDatePicker = false
    private let datePickerSheetHeight: CGFloat = 300

    init(
        mode: Mode,
        store: MemberContextStore,
        shareUseCase: ShareMemberUseCase? = nil,
        inviteUseCase: MemberInviteUseCase? = nil,
        nearbyTransport: NearbyShareTransport? = nil,
        initialPendingTicket: String? = nil,
        onBindingAccepted: (() -> Void)? = nil,
        onCreatedMemberCompleted: ((Member) -> Void)? = nil,
        homeDependencies: HomeFeatureDependencies? = nil
    ) {
        self.store = store
        self.shareUseCase = shareUseCase
        self.inviteUseCase = inviteUseCase
        self.nearbyTransport = nearbyTransport
        self.initialPendingTicket = initialPendingTicket
        self.onBindingAccepted = onBindingAccepted
        self.onCreatedMemberCompleted = onCreatedMemberCompleted
        self.homeDependencies = homeDependencies
        _bindViewModel = StateObject(
            wrappedValue: AddFamilyMemberViewModel(
                mode: mode,
                shareUseCase: shareUseCase,
                inviteUseCase: inviteUseCase,
                nearbyTransport: nearbyTransport,
                initialPendingTicket: initialPendingTicket
            )
        )

        switch mode {
        case .create, .bind, .acceptInvite:
            _name = State(initialValue: "")
            _relationshipCode = State(initialValue: MemberRelationshipCatalog.defaultCode)
            _gender = State(initialValue: MemberRelationshipCatalog.unsetGender)
            _birthDate = State(initialValue: nil)
        case .edit(let member):
            _name = State(initialValue: member.name)
            _relationshipCode = State(initialValue: MemberRelationshipCatalog.compatibleCode(from: member.relationship))
            _gender = State(initialValue: MemberRelationshipCatalog.editableGender(from: member.gender))
            _birthDate = State(initialValue: member.birthDate)
        }
    }

    private var navigationTitle: String {
        switch bindViewModel.mode {
        case .create:
            return L10n.text("home.members.add.title")
        case .edit:
            return L10n.text("home.members.edit")
        case .bind, .acceptInvite:
            return L10n.text("home.members.bind.title")
        }
    }

    private var actionTitle: String {
        switch bindViewModel.mode {
        case .create:
            return L10n.text("home.members.add.save")
        case .edit:
            return L10n.text("home.members.update")
        case .bind, .acceptInvite:
            return L10n.text("home.members.add.save")
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && birthDate != nil
            && MemberRelationshipCatalog.isSelectableGender(gender)
    }

    var body: some View {
        if case .create = bindViewModel.mode, let homeDependencies/*, false*/ {
            MemberSetupFlowView(
                store: store,
                homeDependencies: homeDependencies,
                onAppear: {
                    Task {
                        await bindViewModel.consumeInitialPendingTicketIfNeeded()
                    }
                },
                onMemberCreated: { member in
                    onCreatedMemberCompleted?(member)
                }
            )
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch bindViewModel.mode {
                case .bind(_, let resolved):
                    bindMemberContent(resolved)
                case .acceptInvite(_, let preview):
                    acceptInviteContent(preview)
                case .create, .edit:
                    createOrEditContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.ok")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if bindViewModel.canShowScanner || bindViewModel.canShowReceiveNearby {
                    Menu {
                        if bindViewModel.canShowScanner {
                            Button {
                                bindViewModel.showMemberScanner = true
                                triggerHaptic(style: .light)
                            } label: {
                                Label(L10n.text("home.members.add.scan"), systemImage: "qrcode.viewfinder")
                            }
                        }
                        if bindViewModel.canShowReceiveNearby {
                            Button {
                                if bindViewModel.isReceivingNearby {
                                    bindViewModel.stopNearbyReceive()
                                } else {
                                    bindViewModel.startNearbyReceive()
                                }
                                triggerHaptic(style: .light)
                            } label: {
                                Label(
                                    bindViewModel.isReceivingNearby
                                        ? L10n.text("home.members.share.nearby.receive_stop")
                                        : L10n.text("home.members.add.receive_nearby"),
                                    systemImage: "antenna.radiowaves.left.and.right"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "plus.viewfinder")
                    }
                }
            }
        }
        .onDisappear {
            bindViewModel.stopNearbyReceive()
        }
        .overlay {
            if bindViewModel.isResolvingShare {
                ProgressView(L10n.text("home.members.share.scan.resolving"))
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                selectedDate: $birthDate,
                datePickerSheetHeight: datePickerSheetHeight
            )
        }
        .fullScreenCover(isPresented: $bindViewModel.showMemberScanner) {
            QRCodeScannerView { ticket in
                bindViewModel.presentShareAcceptAfterScanner(ticket: ticket)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: bindViewModel.mode.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: relationshipCode)
        .task {
            if case .create = bindViewModel.mode {
                await bindViewModel.consumeInitialPendingTicketIfNeeded()
            }
        }
        .alert(
            L10n.text("home.members.bind.title"),
            isPresented: shareAlertPresented
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {
                bindViewModel.shareAlertMessage = nil
            }
        } message: {
            if let message = bindViewModel.shareAlertMessage {
                Text(message)
            }
        }
        }
    }

    private var shareAlertPresented: Binding<Bool> {
        Binding(
            get: { bindViewModel.shareAlertMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    bindViewModel.shareAlertMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private var createOrEditContent: some View {
        if bindViewModel.isReceivingNearby, let transport = nearbyTransport {
            NearbyShareReceivePanel(transport: transport) {
                bindViewModel.stopNearbyReceive()
            }
        }

        if let message = bindViewModel.shareErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        relationshipSection
        nameSection
        genderSection
        birthDateSection

        Text(L10n.text("home.members.hint"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)

        Button {
            Task {
                await save()
            }
        } label: {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(actionTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(canSave ? Color.accentColor : Color(uiColor: .systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isSaving)
        .padding(.top, 4)
    }
    

    @ViewBuilder
    private func bindMemberContent(_ resolved: SparkMedicalMemberAPI.ShareResolveResponse) -> some View {
        Text(
            String(
                format: L10n.text("home.members.bind.inviter"),
                resolved.inviter.displayName
            )
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 8) {
            Text(resolved.member.name)
                .font(.title2.weight(.bold))
            Text(bindMemberSummary(resolved.member))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))

        Text(L10n.text("home.members.bind.summary"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)

        MemberRelationshipPicker(
            relationshipCode: $bindViewModel.relationshipCode,
            customRelationship: $bindViewModel.customRelationship
        )

        if resolved.alreadyBound {
            Text(L10n.text("home.members.bind.already_bound"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let message = bindViewModel.shareErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Button {
            Task {
                if await bindViewModel.acceptBinding() != nil {
                    onBindingAccepted?()
                    dismiss()
                }
            }
        } label: {
            HStack {
                Spacer()
                if bindViewModel.isAccepting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.text("home.members.bind.confirm"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(bindViewModel.canConfirmBinding ? Color.accentColor : Color(uiColor: .systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!bindViewModel.canConfirmBinding || bindViewModel.isAccepting)

        Button {
            bindViewModel.cancelBindMode()
        } label: {
            Text(L10n.text("home.members.bind.cancel"))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func acceptInviteContent(_ preview: SparkMedicalMemberAPI.PendingInviteItem) -> some View {
        Text(
            String(
                format: L10n.text("home.members.bind.inviter"),
                preview.inviter.displayName
            )
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 8) {
            Text(preview.member.name)
                .font(.title2.weight(.bold))
            Text(bindMemberSummary(preview.member))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))

        Text(L10n.text("home.members.bind.summary"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)

        MemberRelationshipPicker(
            relationshipCode: $bindViewModel.relationshipCode,
            customRelationship: $bindViewModel.customRelationship
        )

        if let message = bindViewModel.shareErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }

        Button {
            Task {
                if await bindViewModel.acceptBinding() != nil {
                    onBindingAccepted?()
                    dismiss()
                }
            }
        } label: {
            HStack {
                Spacer()
                if bindViewModel.isAccepting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.text("home.members.invite.accept"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .background(bindViewModel.canConfirmBinding ? Color.accentColor : Color(uiColor: .systemGray3))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!bindViewModel.canConfirmBinding || bindViewModel.isAccepting)

        Button {
            Task {
                await bindViewModel.rejectCurrentInviteIfNeeded()
                dismiss()
            }
        } label: {
            Text(L10n.text("home.members.invite.reject"))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func bindMemberSummary(_ member: SparkMedicalMemberAPI.ShareResolveResponse.MemberSummary) -> String {
        let genderText: String
        switch member.gender.lowercased() {
        case "male":
            genderText = L10n.text("home.members.gender.male")
        case "female":
            genderText = L10n.text("home.members.gender.female")
        default:
            genderText = L10n.text("home.members.gender.unknown")
        }
        if let birthDate = member.birthDate {
            return "\(genderText) · \(birthDate.formatted(date: .long, time: .omitted))"
        }
        return genderText
    }

    private var relationshipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldTitle(L10n.text("home.members.field.relationship"), required: true)

            VStack(spacing: 12) {
                ForEach(MemberRelationshipCatalog.rows, id: \.self) { rowCodes in
                    HStack(spacing: 12) {
                        ForEach(rowCodes, id: \.self) { code in
                            let option = MemberRelationshipCatalog.option(for: code)
                            relationshipChip(
                                title: option.title,
                                isSelected: relationshipCode == code
                            ) {
                                relationshipCode = code
                                if let inferredGender = option.inferredGender {
                                    gender = inferredGender
                                } else {
                                    gender = MemberRelationshipCatalog.unsetGender
                                }
                                triggerHaptic(style: .light)
                            }
                        }
                    }
                }
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldTitle(L10n.text("home.members.field.name"), required: true)

            TextField(L10n.text("home.members.field.name_placeholder"), text: $name)
                .textInputAutocapitalization(.words)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
        }
    }

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldTitle(L10n.text("home.members.field.gender"), required: true)

            HStack(spacing: 12) {
                genderChip(title: L10n.text("home.members.gender.male"), value: "male")
                genderChip(title: L10n.text("home.members.gender.female"), value: "female")
            }
        }
    }

    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldTitle(L10n.text("home.members.field.birth_date"), required: true)

            Button {
                showDatePicker = true
                triggerHaptic(style: .light)
            } label: {
                HStack {
                    Text(formattedDate)
                        .font(.body)
                        .foregroundStyle(birthDate == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var formattedDate: String {
        guard let birthDate else { return L10n.text("home.members.field.birth_date_placeholder") }
        return birthDate.formatted(date: .long, time: .omitted)
    }

    private func fieldTitle(_ title: String, required: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            if required {
                Text("*")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemRed))
            }
        }
    }

    private func relationshipChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func genderChip(title: String, value: String) -> some View {
        Button {
            gender = value
            triggerHaptic(style: .light)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: gender == value ? "record.circle.fill" : "circle")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.body)
            }
            .foregroundStyle(gender == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(gender == value ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch bindViewModel.mode {
        case .create:
            let member = await store.addMember(
                name: trimmedName,
                relationship: relationshipCode,
                gender: gender,
                birthDate: birthDate
            )
            guard member != nil else { return }
        case .edit(let member):
            let didSave = await store.updateMember(
                member,
                name: trimmedName,
                relationship: relationshipCode,
                gender: gender,
                birthDate: birthDate
            )
            guard didSave else { return }
        case .bind, .acceptInvite:
            return
        }
        dismiss()
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}
#if DEBUG
#Preview {
    AddFamilyMemberView(mode: .create, store: HomeViewModel.preview.memberContextStoreForBinding)
}
#endif
private struct DatePickerSheet: View {
    @Binding var selectedDate: Date?
    let datePickerSheetHeight: CGFloat

    @State private var tempDate: Date

    init(selectedDate: Binding<Date?>, datePickerSheetHeight: CGFloat) {
        self._selectedDate = selectedDate
        self.datePickerSheetHeight = datePickerSheetHeight
        self._tempDate = State(initialValue: selectedDate.wrappedValue ?? Calendar.current.date(byAdding: .year, value: -24, to: Date()) ?? Date())
    }

    var body: some View {
        AdaptiveSheetContainer.fixed(
            height: datePickerSheetHeight,
            cancelTitle: L10n.text("common.cancel"),
            confirmTitle: L10n.text("common.done"),
            cancelColor: .secondary,
            confirmColor: .accentColor,
            onCancel: {},
            onConfirm: {
                selectedDate = tempDate
            }
        ) {
            DatePicker(
                L10n.text("home.members.field.birth_date"),
                selection: $tempDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

enum MemberRelationshipCatalog {
    struct Option {
        let code: String
        let title: String
        let inferredGender: String?
    }

    static let defaultCode = "self"
    /// 未选择性别（本人等需用户手动勾选）。
    static let unsetGender = ""

    static func isSelectableGender(_ gender: String) -> Bool {
        switch gender.lowercased() {
        case "male", "female":
            return true
        default:
            return false
        }
    }

    static func editableGender(from stored: String) -> String {
        isSelectableGender(stored) ? stored.lowercased() : unsetGender
    }

    static let rows: [[String]] = [
        ["father", "mother", "husband", "wife"],
        ["son", "daughter", "older_brother", "younger_brother"],
        ["older_sister", "younger_sister", "grandfather", "grandmother"],
        ["maternal_grandfather", "maternal_grandmother", "self", "other"]
    ]

    static func option(for code: String) -> Option {
        switch code {
        case "father":
            return Option(code: code, title: L10n.text("home.members.relationship.father"), inferredGender: "male")
        case "mother":
            return Option(code: code, title: L10n.text("home.members.relationship.mother"), inferredGender: "female")
        case "husband":
            return Option(code: code, title: L10n.text("home.members.relationship.husband"), inferredGender: "male")
        case "wife":
            return Option(code: code, title: L10n.text("home.members.relationship.wife"), inferredGender: "female")
        case "son":
            return Option(code: code, title: L10n.text("home.members.relationship.son"), inferredGender: "male")
        case "daughter":
            return Option(code: code, title: L10n.text("home.members.relationship.daughter"), inferredGender: "female")
        case "older_brother":
            return Option(code: code, title: L10n.text("home.members.relationship.older_brother"), inferredGender: "male")
        case "younger_brother":
            return Option(code: code, title: L10n.text("home.members.relationship.younger_brother"), inferredGender: "male")
        case "older_sister":
            return Option(code: code, title: L10n.text("home.members.relationship.older_sister"), inferredGender: "female")
        case "younger_sister":
            return Option(code: code, title: L10n.text("home.members.relationship.younger_sister"), inferredGender: "female")
        case "grandfather":
            return Option(code: code, title: L10n.text("home.members.relationship.grandfather"), inferredGender: "male")
        case "grandmother":
            return Option(code: code, title: L10n.text("home.members.relationship.grandmother"), inferredGender: "female")
        case "maternal_grandfather":
            return Option(code: code, title: L10n.text("home.members.relationship.maternal_grandfather"), inferredGender: "male")
        case "maternal_grandmother":
            return Option(code: code, title: L10n.text("home.members.relationship.maternal_grandmother"), inferredGender: "female")
        case "self":
            return Option(code: code, title: L10n.text("home.members.relationship.self"), inferredGender: nil)
        case "family":
            return Option(code: "self", title: L10n.text("home.members.relationship.self"), inferredGender: nil)
        default:
            return Option(code: "other", title: L10n.text("home.members.relationship.other"), inferredGender: nil)
        }
    }

    static func compatibleCode(from relationship: String) -> String {
        let normalized = relationship.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "本人": return "self"
        case "爸爸": return "father"
        case "妈妈": return "mother"
        case "老公": return "husband"
        case "老婆": return "wife"
        case "儿子": return "son"
        case "女儿": return "daughter"
        case "哥哥": return "older_brother"
        case "弟弟": return "younger_brother"
        case "姐姐": return "older_sister"
        case "妹妹": return "younger_sister"
        case "爷爷": return "grandfather"
        case "奶奶": return "grandmother"
        case "外公": return "maternal_grandfather"
        case "外婆": return "maternal_grandmother"
        case "家人": return "other"
        case "self", "father", "mother", "husband", "wife", "son", "daughter", "older_brother", "younger_brother", "older_sister", "younger_sister", "grandfather", "grandmother", "maternal_grandfather", "maternal_grandmother", "other":
            return normalized
        default:
            return "other"
        }
    }

    static func displayTitle(for relationship: String) -> String {
        option(for: compatibleCode(from: relationship)).title
    }
}
