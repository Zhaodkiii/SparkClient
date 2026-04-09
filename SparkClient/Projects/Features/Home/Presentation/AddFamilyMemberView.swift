//
//  AddFamilyMemberView.swift
//  SparkClient
//
//  Created by 話 on 2026/4/9.
//

import SwiftUI

struct  AddFamilyMemberView: View {
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
#Preview {
    AddFamilyMemberView(mode:  .create, viewModel: .preview)
}


enum MemberRelationshipCatalog {
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
