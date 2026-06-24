import SwiftUI

struct AllergyRecordFormView: View {
    let initial: AllergyRecordFormDraft
    let onSubmit: (AllergyRecordFormDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var allergies: [String]
    @State private var details: [String: MedicalGuideAllergyDetail]
    @State private var allergyHistory: String
    @State private var searchText = ""
    @State private var customAllergenText = ""
    @State private var focusedAllergy: String?

    private let severityOptions = AllergyRecordFormSupport.severityOptions
    private let reactionOptions = AllergyRecordFormSupport.reactionOptions

    private var filteredCategories: [AllergyCategoryGroup] {
        AllergyRecordFormSupport.filteredCategories(matching: searchText)
    }

    init(initial: AllergyRecordFormDraft, onSubmit: @escaping (AllergyRecordFormDraft) -> Void) {
        self.initial = initial
        self.onSubmit = onSubmit
        _allergies = State(initialValue: initial.allergies)
        _details = State(initialValue: initial.details)
        _allergyHistory = State(initialValue: initial.allergyHistory)
        _focusedAllergy = State(initialValue: initial.allergies.last)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introSection
                quickSelectionSection
                customAllergenSection
                if allergies.isEmpty == false {
                    allergyDetailsCard
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("member.setup.medical.allergy.allergy.3ffc39"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: Text(L10n.text("member.setup.medical.allergy.allergy.a8c141"))
        )
        .sparkFormBottomBar(
            canSubmit: allergies.isEmpty == false,
            saveTitle: L10n.text("common.done"),
            onCancel: { dismiss() },
            onSave: { saveNow() }
        )
        .onChange(of: allergies) { newValue in
            if let focusedAllergy, newValue.contains(focusedAllergy) == false {
                self.focusedAllergy = newValue.last
            }
            if focusedAllergy == nil {
                focusedAllergy = newValue.last
            }
            let validKeys = Set(newValue)
            details = details.filter { validKeys.contains($0.key) }
        }
    }

    private var introSection: some View {
        Text(AllergyRecordFormSupport.introText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("member.setup.medical.allergy.allergy.92231a"))
                .font(.headline.weight(.semibold))

            VStack(spacing: 0) {
                if filteredCategories.isEmpty {
                    Text(L10n.text("member.setup.medical.allergy.allergy.4e5cec"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(filteredCategories.enumerated()), id: \.element.id) { index, category in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.title, systemImage: category.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 112), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(category.allergens, id: \.self) { allergen in
                                    allergenChip(allergen, category: category.detailCategory)
                                }
                            }
                        }
                        .padding(.vertical, 12)

                        if index < filteredCategories.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var customAllergenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("member.setup.medical.allergy.allergy.889a45"))
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.text("member.setup.medical.allergy.allergy.a680ca"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.text("member.setup.medical.allergy.allergy.76e483"), systemImage: "pencil.line")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("例如：某些香水、蚕豆...", text: $customAllergenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(uiColor: .systemBackground))
                        )
                        .submitLabel(.done)
                        .onSubmit { addCustomAllergen() }
                }

                Button(action: addCustomAllergen) {
                    Label(L10n.text("member.setup.medical.allergy.allergy.5e3640"), systemImage: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(canAddCustomAllergen ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canAddCustomAllergen ? Color.accentColor : Color(uiColor: .systemGray4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(canAddCustomAllergen == false)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private var canAddCustomAllergen: Bool {
        resolvedCustomAllergenName.isEmpty == false
    }

    private var resolvedCustomAllergenName: String {
        let custom = customAllergenText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty == false { return custom }
        return searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allergyDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("member.setup.medical.allergy.allergy.3e036f"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("member.setup.medical.allergy.allergy.de5ce8"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SparkTagFlowLayout(spacing: 8) {
                    ForEach(allergies, id: \.self) { allergen in
                        selectedAllergenTag(allergen)
                    }
                }
            }

            if let focusedAllergy {
                Divider()

                Text(AllergyRecordFormSupport.displayAllergen(focusedAllergy))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("member.setup.medical.allergy.allergy.f61739"), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        severityPicker(for: focusedAllergy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("member.setup.medical.allergy.allergy.7e26a0"), systemImage: "allergens")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        reactionPicker(for: focusedAllergy)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label(L10n.text("member.setup.medical.allergy.allergy.d28cc7"), systemImage: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextEditor(text: detailNotesBinding(for: focusedAllergy))
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func allergenChip(_ allergen: String, category: String) -> some View {
        let isSelected = allergies.contains(allergen)
        return Button {
            if isSelected {
                if focusedAllergy == allergen {
                    toggle(allergen, category: category)
                } else {
                    focusedAllergy = allergen
                }
            } else {
                toggle(allergen, category: category)
            }
        } label: {
            Text(AllergyRecordFormSupport.displayAllergen(allergen))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func selectedAllergenTag(_ allergen: String) -> some View {
        let isFocused = focusedAllergy == allergen
        return HStack(spacing: 6) {
            Button {
                focusedAllergy = allergen
            } label: {
                Text(AllergyRecordFormSupport.displayAllergen(allergen))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocused ? Color.accentColor : .primary)
            }
            .buttonStyle(.plain)

            Button {
                removeAllergen(allergen)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
        )
    }

    private func severityPicker(for allergen: String) -> some View {
        HStack(spacing: 8) {
            ForEach(severityOptions, id: \.self) { option in
                let isSelected = detail(for: allergen).severity == option
                Button {
                    updateDetail(for: allergen) { $0.severity = option }
                } label: {
                    Text(AllergyRecordFormSupport.displaySeverity(option))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? AllergyRecordFormSupport.severityTint(option) : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AllergyRecordFormSupport.severityTint(option).opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reactionPicker(for allergen: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(reactionOptions, id: \.self) { reaction in
                let isSelected = detail(for: allergen).reactions.contains(reaction)
                Button {
                    updateDetail(for: allergen) { detail in
                        if detail.reactions.contains(reaction) {
                            detail.reactions.removeAll { $0 == reaction }
                        } else {
                            detail.reactions.append(reaction)
                        }
                    }
                } label: {
                    Text(AllergyRecordFormSupport.displayReaction(reaction))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ allergen: String, category: String) {
        if allergies.contains(allergen) {
            removeAllergen(allergen)
        } else {
            allergies.append(allergen)
            focusedAllergy = allergen
            if details[allergen] == nil {
                details[allergen] = MedicalGuideAllergyDetail(category: category)
            } else {
                details[allergen]?.category = category
            }
        }
    }

    private func removeAllergen(_ allergen: String) {
        allergies.removeAll { $0 == allergen }
        details.removeValue(forKey: allergen)
        if focusedAllergy == allergen {
            focusedAllergy = allergies.last
        }
    }

    private func addCustomAllergen() {
        let name = resolvedCustomAllergenName
        guard name.isEmpty == false else { return }
        guard allergies.contains(name) == false else {
            customAllergenText = ""
            focusedAllergy = name
            return
        }
        allergies.append(name)
        focusedAllergy = name
        if details[name] == nil {
            details[name] = MedicalGuideAllergyDetail(category: AllergyRecordFormSupport.customCategory)
        }
        customAllergenText = ""
        searchText = ""
    }

    private func detail(for allergen: String) -> MedicalGuideAllergyDetail {
        details[allergen] ?? MedicalGuideAllergyDetail()
    }

    private func updateDetail(for allergen: String, update: (inout MedicalGuideAllergyDetail) -> Void) {
        var draft = detail(for: allergen)
        update(&draft)
        details[allergen] = draft
    }

    private func detailNotesBinding(for allergen: String) -> Binding<String> {
        Binding(
            get: { detail(for: allergen).notes },
            set: { newValue in
                updateDetail(for: allergen) { $0.notes = newValue }
            }
        )
    }

    private func saveNow() {
        allergyHistory = allergies
            .compactMap { allergen in
                let summary = AllergyRecordFormSupport.summaryLine(name: allergen, detail: details[allergen])
                return summary == allergen ? nil : summary
            }
            .joined(separator: " / ")
        onSubmit(
            AllergyRecordFormDraft(
                allergies: allergies,
                details: details,
                allergyHistory: allergyHistory
            )
        )
        dismiss()
    }
}
