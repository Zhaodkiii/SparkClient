import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var medicalDocumentUploadViewModel: MedicalDocumentUploadViewModel
    let session: UserSession
    var onOpenHealthTimeline: (() -> Void)?

    @State private var hasLoaded = false
    @State private var memberActionTarget: Member?
    @State private var showDeleteConfirmation = false
    @State private var addMemberMode: AddFamilyMemberView.Mode?
    @State private var showMedicalDocumentUpload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                medicalInfoSection
                healthBasicsSection
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
            NavigationView {
                AddFamilyMemberView(mode: mode, viewModel: viewModel)
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
            await viewModel.load()
        }
        .fullScreenCover(isPresented: $showMedicalDocumentUpload) {
            NavigationView {
                MedicalDocumentUploadHostView(viewModel: medicalDocumentUploadViewModel)
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
            Text(L10n.homeGreeting(session.displayName))
                .font(.title.weight(.bold))

            Text(L10n.text("home.mode.remote"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(
                    session.signedInAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onOpenHealthTimeline?()
                    triggerHaptic(style: .light)
                } label: {
                    Label(L10n.text("home.action.timeline"), systemImage: "waveform.path.ecg")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
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
                    medicalCard(card)
                }
            }
        }
    }

    private func medicalCard(_ card: HomeDashboard.MedicalCard) -> some View {
        Button {
            onOpenHealthTimeline?()
            triggerHaptic(style: .light)
        } label: {
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
        .buttonStyle(.plain)
    }

    private var healthBasicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("home.health_basics.title"), systemImage: "heart.text.square")
                    .font(.headline)
                Spacer()
                Button {
                    Task {
                        await viewModel.requestHealthAuthorization()
                    }
                    triggerHaptic(style: .light)
                } label: {
                    Label(L10n.text("home.health_basics.authorize"), systemImage: "hand.raised")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if viewModel.dashboard?.canShowHealthBasics == false {
                infoCard(text: L10n.text("home.health_basics.only_self"), symbol: "person.crop.circle.badge.exclamationmark")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(viewModel.dashboard?.motion.healthBasics ?? [], id: \.id) { item in
                        healthBasicCard(item)
                    }
                }

                if let status = viewModel.dashboard?.motion.healthAuthorizationStatus, status != .authorized {
                    infoCard(text: authorizationStatusText(status), symbol: "heart.slash")
                }
            }
        }
    }

    private func healthBasicCard(_ item: HomeDashboard.HealthBasicItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemIndigo))

            Text(healthTitle(for: item.id))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(healthValue(for: item))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let recordedAt = item.recordedAt {
                Text(recordedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func infoCard(text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemOrange))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
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

    private func healthTitle(for kind: HomeDashboard.HealthBasicItem.Kind) -> String {
        switch kind {
        case .steps:
            return L10n.text("metric.steps")
        case .weight:
            return L10n.text("metric.weight")
        case .sleep:
            return L10n.text("metric.sleep")
        case .heartRate:
            return L10n.text("metric.heart_rate")
        }
    }

    private func healthValue(for item: HomeDashboard.HealthBasicItem) -> String {
        guard let value = item.value else { return L10n.text("common.placeholder") }

        switch item.id {
        case .steps:
            return "\(Int(value)) \(item.unit)"
        case .heartRate:
            return "\(Int(value)) \(item.unit)"
        case .weight, .sleep:
            return String(format: "%.1f %@", locale: Locale.current, value, item.unit)
        }
    }

    private func authorizationStatusText(_ status: HomeDashboard.HealthAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return L10n.text("home.health_basics.authorized")
        case .notDetermined:
            return L10n.text("home.health_basics.not_determined")
        case .denied:
            return L10n.text("home.health_basics.denied")
        case .unavailable:
            return L10n.text("home.health_basics.unavailable")
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

/// Member chip with a per-instance action menu (matches Health `PatientButton` + `confirmationDialog` pattern).
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

private struct AddFamilyMemberView: View {
    enum Mode: Identifiable {
        case create
        case edit(Member)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let member):
                return "edit-\(member.id)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @ObservedObject var viewModel: HomeViewModel

    @State private var name: String
    @State private var relationshipCode: String
    @State private var gender: String
    @State private var birthDate: Date?
    @State private var isSaving = false
    @State private var showDatePicker = false

    init(mode: Mode, viewModel: HomeViewModel) {
        self.mode = mode
        self.viewModel = viewModel

        switch mode {
        case .create:
            _name = State(initialValue: "")
            _relationshipCode = State(initialValue: MemberRelationshipCatalog.defaultCode)
            _gender = State(initialValue: MemberRelationshipCatalog.defaultGender)
            _birthDate = State(initialValue: nil)
        case .edit(let member):
            _name = State(initialValue: member.name)
            _relationshipCode = State(initialValue: MemberRelationshipCatalog.compatibleCode(from: member.relationship))
            _gender = State(initialValue: member.gender)
            _birthDate = State(initialValue: member.birthDate)
        }
    }

    private var title: String {
        switch mode {
        case .create:
            return L10n.text("home.members.create")
        case .edit:
            return L10n.text("home.members.edit")
        }
    }

    private var actionTitle: String {
        switch mode {
        case .create:
            return L10n.text("home.members.save")
        case .edit:
            return L10n.text("home.members.update")
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && birthDate != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.ok")) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationView {
                VStack {
                    DatePicker(
                        L10n.text("home.members.field.birth_date"),
                        selection: Binding(
                            get: { birthDate ?? Calendar.current.date(byAdding: .year, value: -24, to: Date()) ?? Date() },
                            set: { birthDate = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 16)
                .navigationTitle(L10n.text("home.members.select_birth_date"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text("common.ok")) {
                            showDatePicker = false
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: relationshipCode)
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
                genderChip(title: L10n.text("home.members.gender.unknown"), value: "unknown")
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
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
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

        switch mode {
        case .create:
            await viewModel.addMember(
                name: trimmedName,
                relationship: relationshipCode,
                gender: gender,
                birthDate: birthDate
            )
        case .edit(let member):
            await viewModel.updateMember(
                member,
                name: trimmedName,
                relationship: relationshipCode,
                gender: gender,
                birthDate: birthDate
            )
        }

        dismiss()
    }

    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private enum MemberRelationshipCatalog {
    struct Option {
        let code: String
        let title: String
        let inferredGender: String?
    }

    static let defaultCode = "self"
    static let defaultGender = "unknown"

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

#Preview("Light") {
    NavigationView {
        HomeView(
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            session: UserSession(
                profileID: UUID(),
                remoteUserID: "preview-001",
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now
            )
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationView {
        HomeView(
            viewModel: .preview,
            medicalDocumentUploadViewModel: .preview(),
            session: UserSession(
                profileID: UUID(),
                remoteUserID: "preview-001",
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: .now
            )
        )
    }
    .preferredColorScheme(.dark)
}

private extension HomeViewModel {
    static var preview: HomeViewModel {
        let now = Date()
        let profileID = UUID()
        let memberA = Member(id: 1, name: "本人", gender: "female", relationship: "self", birthDate: now.addingTimeInterval(-86_400 * 365 * 30), isPrimary: true)
        let memberB = Member(id: 2, name: "妈妈", gender: "female", relationship: "mother", birthDate: now.addingTimeInterval(-86_400 * 365 * 56), isPrimary: false)

        let dashboard = HomeDashboard(
            profile: UserProfile(
                id: profileID,
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
                HomeDashboard.MedicalCard(id: .medications, count: 96, latestDate: now.addingTimeInterval(-86_400 * 3), symbol: "pills.fill")
            ]),
            motion: HomeMotionHealthOverview(
                healthBasics: [
                    HomeDashboard.HealthBasicItem(id: .steps, value: 9210, unit: "steps", symbol: "figure.walk.motion", recordedAt: now),
                    HomeDashboard.HealthBasicItem(id: .weight, value: 63.6, unit: "kg", symbol: "scalemass.fill", recordedAt: now.addingTimeInterval(-4000)),
                    HomeDashboard.HealthBasicItem(id: .sleep, value: 7.2, unit: "h", symbol: "moon.stars.fill", recordedAt: now.addingTimeInterval(-8000)),
                    HomeDashboard.HealthBasicItem(id: .heartRate, value: 71, unit: "bpm", symbol: "heart.text.square.fill", recordedAt: now.addingTimeInterval(-2000))
                ],
                healthAuthorizationStatus: .authorized,
                isApplicable: true
            )
        )

        let sessionStore = AppSessionStore(
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: PreviewAuthRepository())
        )
        sessionStore.setAuthenticated(
            UserSession(
                profileID: profileID,
                remoteUserID: "preview-001",
                email: "preview@spark.com",
                displayName: "Spark User",
                signedInAt: now
            )
        )

        let mockMemberRepository = PreviewHomeMemberRepository(snapshot: .empty)
        let mockHealthRepository = PreviewHomeHealthRepository()

        let previewLogger = ConsoleLogger()
        let viewModel = HomeViewModel(
            sessionStore: sessionStore,
            loadHomeMedicalOverviewUseCase: LoadHomeMedicalOverviewUseCase(
                userProfileRepository: PreviewUserProfileRepository(profile: dashboard.profile),
                memberRepository: mockMemberRepository,
                logger: previewLogger
            ),
            loadHomeMotionHealthUseCase: LoadHomeMotionHealthUseCase(
                healthDataRepository: mockHealthRepository,
                logger: previewLogger
            ),
            manageHomeMemberUseCase: ManageHomeMemberUseCase(memberRepository: mockMemberRepository),
            requestHomeHealthAuthorizationUseCase: RequestHomeHealthAuthorizationUseCase(healthDataRepository: mockHealthRepository),
            patientContextStore: PatientContextStore(),
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

    func fetchProfile(id: UUID) async throws -> UserProfile? {
        profile
    }

    func fetchLastActiveProfile() async throws -> UserProfile? {
        profile
    }

    func upsertProfile(
        email: String,
        displayName: String,
        signedInAt: Date
    ) async throws -> UserProfile {
        UserProfile(
            id: profile.id,
            email: email,
            displayName: displayName,
            createdAt: profile.createdAt,
            lastSignedInAt: signedInAt
        )
    }
}

private actor PreviewHomeMemberRepository: HomeMemberRepository {
    private var snapshot: MedicalDataSnapshot

    init(snapshot: MedicalDataSnapshot) {
        self.snapshot = snapshot
    }

    func refreshRemoteSnapshot() async throws {}

    func loadMembers() async -> [Member] {
        snapshot.members
    }

    func loadSnapshot(memberID: Int) async -> MedicalDataSnapshot {
        var copy = snapshot
        copy.medicalCases = snapshot.medicalCases.filter { $0.memberID == memberID }
        copy.healthExamReports = snapshot.healthExamReports.filter { $0.memberID == memberID }
        copy.examinationReports = snapshot.examinationReports.filter { $0.memberID == memberID }
        copy.medications = snapshot.medications.filter { $0.memberID == memberID }
        copy.medicationTakenRecords = snapshot.medicationTakenRecords.filter { $0.memberID == memberID }
        return copy
    }

    func createMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {}

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {}

    func deleteMember(_ member: Member) async throws {}
}

private struct PreviewHomeHealthRepository: HomeHealthDataRepository {
    func currentAuthorizationStatus() async -> HomeDashboard.HealthAuthorizationStatus { .authorized }

    func requestAuthorizationIfNeeded() async throws -> HomeDashboard.HealthAuthorizationStatus { .authorized }

    func fetchHealthBasics() async throws -> [HomeDashboard.HealthBasicItem] { [] }
}

private struct PreviewAuthRepository: AuthRepository {
    func restoreSession() async -> UserSession? { nil }

    func signInWithApple(payload: AppleSignInPayload) async throws -> UserSession {
        throw NSError(domain: "PreviewAuthRepository", code: -1)
    }

    func signOut() async throws {}
}
