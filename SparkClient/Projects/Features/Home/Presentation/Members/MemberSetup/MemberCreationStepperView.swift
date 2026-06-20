//import SwiftUI
//#if canImport(UIKit)
//import UIKit
//#endif
//
//struct MemberCreationStepperView: View {
//    enum Step: Int, CaseIterable {
//        case basicInfo
//        case relationship
//        case modules
//    }
//
//    enum ModuleSheet: String, Identifiable {
//        case medical
//        case nutrition
//
//        var id: String { rawValue }
//    }
//
//    enum MaintenanceModule: String, CaseIterable, Identifiable {
//        case medical
//        case nutrition
//        case dailyHealth = "daily_health"
//
//        var id: String { rawValue }
//    }
//
//    @Environment(\.dismiss) private var dismiss
//
//    let store: MemberContextStore
//    let homeDependencies: HomeFeatureDependencies
//    let shareUseCase: ShareMemberUseCase?
//    let inviteUseCase: MemberInviteUseCase?
//    let nearbyTransport: NearbyShareTransport?
//    let initialPendingTicket: String?
//    let onBindingAccepted: (() -> Void)?
//    let onCreateAppear: @Sendable () async -> Void
//
//    @State private var step: Step = .basicInfo
//    @State private var name = ""
//    @State private var birthDate: Date?
//    @State private var relationshipCode = MemberRelationshipCatalog.defaultCode
//    @State private var gender = MemberRelationshipCatalog.unsetGender
//    @State private var isSavingMember = false
//    @State private var createdMember: Member?
//    @State private var selectedModules: Set<MaintenanceModule> = []
//    @State private var completedModules: Set<MaintenanceModule> = []
//    @State private var isPersistingModules = false
//    @State private var activeModuleSheet: ModuleSheet?
//    @State private var alertMessage: String?
//    @State private var showDatePicker = false
//
//    private let datePickerSheetHeight: CGFloat = 300
//
//    private var canAdvanceFromBasicInfo: Bool {
//        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && birthDate != nil
//    }
//
//    private var canAdvanceFromRelationship: Bool {
//        MemberRelationshipCatalog.isSelectableGender(gender)
//    }
//
//    private var stepTitle: String {
//        switch step {
//        case .basicInfo:
//            return L10n.text("home.members.add.title")
//        case .relationship:
//            return L10n.text("home.members.relationship.title", fallback: "成员关系")
//        case .modules:
//            return L10n.text("member.module.selection.title", fallback: "选择维护模块")
//        }
//    }
//
//    private var stepSubtitle: String {
//        switch step {
//        case .basicInfo:
//            return L10n.text("home.members.add.subtitle", fallback: "先填写成员的基础信息")
//        case .relationship:
//            return L10n.text("home.members.relationship.subtitle", fallback: "确认与当前账号的关系与性别")
//        case .modules:
//            return L10n.text("member.module.selection.subtitle", fallback: "至少开启一个模块，后续可以分步完善")
//        }
//    }
//
//    var body: some View {
//        CompatibleNavigationContainer {
//            ScrollView {
//                VStack(alignment: .leading, spacing: 20) {
//                    topCard
//
//                    switch step {
//                    case .basicInfo:
//                        basicInfoPage
//                    case .relationship:
//                        relationshipPage
//                    case .modules:
//                        moduleSelectionPage
//                    }
//                }
//                .padding(.horizontal, 16)
//                .padding(.vertical, 16)
//            }
//            .background(Color(uiColor: .systemGroupedBackground))
//            .navigationTitle(stepTitle)
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button(L10n.text("common.cancel")) {
//                        dismiss()
//                    }
//                }
//            }
//            .sheet(item: $activeModuleSheet) { module in
//                switch module {
//                case .medical:
//                    MemberMedicalSetupSheet(
//                        member: createdMember,
//                        setupUseCase: homeDependencies.memberModuleSetupUseCase
//                    ) { summary in
//                        completedModules.insert(.medical)
//                        selectedModules.insert(.medical)
//                        Task { await persistModuleSelection(module: .medical, isCompleted: true, summaryText: summary) }
//                    }
//                case .nutrition:
//                    MemberNutritionSetupSheet(
//                        member: createdMember,
//                        goalUseCase: homeDependencies.nutritionDependencies.goalUseCase,
//                        setupUseCase: homeDependencies.memberModuleSetupUseCase
//                    ) { summary in
//                        completedModules.insert(.nutrition)
//                        selectedModules.insert(.nutrition)
//                        Task { await persistModuleSelection(module: .nutrition, isCompleted: true, summaryText: summary) }
//                    }
//                }
//            }
//            .sheet(isPresented: $showDatePicker) {
//                DatePickerSheet(
//                    selectedDate: $birthDate,
//                    datePickerSheetHeight: datePickerSheetHeight
//                )
//            }
//            .alert(
//                L10n.text("common.ok"),
//                isPresented: Binding(
//                    get: { alertMessage != nil },
//                    set: { if !$0 { alertMessage = nil } }
//                )
//            ) {
//                Button(L10n.text("common.ok"), role: .cancel) {
//                    alertMessage = nil
//                }
//            } message: {
//                Text(alertMessage ?? "")
//            }
//            .task {
//                await onCreateAppear()
//            }
//        }
//    }
//
//    private var topCard: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            HStack {
//                Text(stepTitle)
//                    .font(.title2.weight(.bold))
//                Spacer()
//                Text("\(step.rawValue + 1)/\(Step.allCases.count)")
//                    .font(.subheadline.weight(.semibold))
//                    .foregroundStyle(.secondary)
//            }
//            Text(stepSubtitle)
//                .font(.footnote)
//                .foregroundStyle(.secondary)
//        }
//        .padding(16)
//        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//    }
//
//    private var basicInfoPage: some View {
//        VStack(alignment: .leading, spacing: 18) {
//            fieldTitle(L10n.text("home.members.field.name"), required: true)
//            TextField(L10n.text("home.members.field.name_placeholder"), text: $name)
//                .textInputAutocapitalization(.words)
//                .font(.body)
//                .padding(.horizontal, 14)
//                .padding(.vertical, 12)
//                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//
//            fieldTitle(L10n.text("home.members.field.birth_date"), required: true)
//            Button {
//                showDatePicker = true
//                triggerHaptic(style: .light)
//            } label: {
//                HStack {
//                    Text(formattedBirthDate)
//                        .foregroundStyle(birthDate == nil ? .secondary : .primary)
//                    Spacer()
//                    Image(systemName: "calendar")
//                        .foregroundStyle(.secondary)
//                }
//                .padding(.horizontal, 14)
//                .padding(.vertical, 12)
//                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//            }
//            .buttonStyle(.plain)
//
//            HStack {
//                Spacer()
//                Button {
//                    guard canAdvanceFromBasicInfo else { return }
//                    step = .relationship
//                } label: {
//                    Text(L10n.text("common.next", fallback: "下一步"))
//                        .font(.headline.weight(.semibold))
//                        .foregroundStyle(.white)
//                        .frame(maxWidth: .infinity)
//                        .padding(.vertical, 14)
//                        .background(canAdvanceFromBasicInfo ? Color.accentColor : Color(uiColor: .systemGray3))
//                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                }
//                .buttonStyle(.plain)
//                .disabled(!canAdvanceFromBasicInfo)
//                Spacer()
//            }
//            .padding(.top, 4)
//        }
//    }
//
//    private var relationshipPage: some View {
//        VStack(alignment: .leading, spacing: 18) {
//            fieldTitle(L10n.text("home.members.field.relationship"), required: true)
//
//            VStack(spacing: 12) {
//                ForEach(MemberRelationshipCatalog.rows, id: \.self) { rowCodes in
//                    HStack(spacing: 12) {
//                        ForEach(rowCodes, id: \.self) { code in
//                            let option = MemberRelationshipCatalog.option(for: code)
//                            relationshipChip(
//                                title: option.title,
//                                isSelected: relationshipCode == code
//                            ) {
//                                relationshipCode = code
//                                if let inferredGender = option.inferredGender {
//                                    gender = inferredGender
//                                } else {
//                                    gender = MemberRelationshipCatalog.unsetGender
//                                }
//                                triggerHaptic(style: .light)
//                            }
//                        }
//                    }
//                }
//            }
//
//            fieldTitle(L10n.text("home.members.field.gender"), required: true)
//            HStack(spacing: 12) {
//                genderChip(title: L10n.text("home.members.gender.male"), value: "male")
//                genderChip(title: L10n.text("home.members.gender.female"), value: "female")
//            }
//
//            HStack(spacing: 12) {
//                Button {
//                    step = .basicInfo
//                } label: {
//                    Text(L10n.text("common.back", fallback: "上一步"))
//                        .font(.headline.weight(.semibold))
//                        .frame(maxWidth: .infinity)
//                        .padding(.vertical, 14)
//                        .background(Color(uiColor: .secondarySystemBackground))
//                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                }
//                .buttonStyle(.plain)
//
//                Button {
//                    Task { await createMemberAndEnterModules() }
//                } label: {
//                    HStack {
//                        if isSavingMember {
//                            ProgressView()
//                        }
//                        Text(L10n.text("common.next", fallback: "下一步"))
//                    }
//                    .font(.headline.weight(.semibold))
//                    .foregroundStyle(.white)
//                    .frame(maxWidth: .infinity)
//                    .padding(.vertical, 14)
//                    .background(canAdvanceFromRelationship ? Color.accentColor : Color(uiColor: .systemGray3))
//                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                }
//                .buttonStyle(.plain)
//                .disabled(!canAdvanceFromRelationship || isSavingMember)
//            }
//            .padding(.top, 4)
//        }
//    }
//
//    private var moduleSelectionPage: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            if let createdMember {
//                memberSummaryCard(member: createdMember)
//            }
//
//            ForEach(visibleModules) { module in
//                moduleRow(module)
//            }
//
//            if isPersistingModules {
//                ProgressView(L10n.text("home.members.save.loading", fallback: "正在保存"))
//                    .frame(maxWidth: .infinity, alignment: .center)
//            }
//
//            Button {
//                Task { await finish() }
//            } label: {
//                HStack {
//                    Spacer()
//                    Text(L10n.text("common.done", fallback: "完成"))
//                        .font(.headline.weight(.semibold))
//                        .foregroundStyle(.white)
//                    Spacer()
//                }
//                .padding(.vertical, 14)
//                .background(canFinish ? Color.accentColor : Color(uiColor: .systemGray3))
//                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//            }
//            .buttonStyle(.plain)
//            .disabled(!canFinish)
//        }
//    }
//
//    private var visibleModules: [MaintenanceModule] {
//        [.medical, .nutrition]
//    }
//
//    private var canFinish: Bool {
//        completedModules.isEmpty == false && isPersistingModules == false
//    }
//
//    @ViewBuilder
//    private func moduleRow(_ module: MaintenanceModule) -> some View {
//        let isSelected = selectedModules.contains(module)
//        VStack(alignment: .leading, spacing: 10) {
//            HStack {
//                Button {
//                    guard module != .dailyHealth, createdMember != nil else { return }
//                    activeModuleSheet = sheet(for: module)
//                } label: {
//                    HStack(spacing: 10) {
//                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
//                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text(moduleTitle(module))
//                                .font(.headline)
//                                .foregroundStyle(.primary)
//                            Text(moduleSubtitle(module))
//                                .font(.footnote)
//                                .foregroundStyle(.secondary)
//                                .multilineTextAlignment(.leading)
//                        }
//                    }
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                }
//                .buttonStyle(.plain)
//
//                if module != .dailyHealth {
//                    Button {
//                        activeModuleSheet = sheet(for: module)
//                    } label: {
//                        Text(L10n.text("home.members.finish", fallback: "去完善"))
//                            .font(.subheadline.weight(.semibold))
//                            .foregroundStyle(createdMember == nil ? .secondary : Color.accentColor)
//                    }
//                    .buttonStyle(.plain)
//                    .disabled(createdMember == nil)
//                } else {
//                    Text(L10n.text("common.preview", fallback: "预留"))
//                        .font(.footnote.weight(.semibold))
//                        .foregroundStyle(.secondary)
//                }
//            }
//            if completedModules.contains(module) {
//                Text(L10n.text("home.members.save.success", fallback: "已完成"))
//                    .font(.footnote)
//                    .foregroundStyle(.green)
//            }
//        }
//        .padding(14)
//        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//    }
//
//    private func moduleTitle(_ module: MaintenanceModule) -> String {
//        switch module {
//        case .medical:
//            return L10n.text("member.module.medical.title", fallback: "医疗模块")
//        case .nutrition:
//            return L10n.text("member.module.nutrition.title", fallback: "饮食健康")
//        case .dailyHealth:
//            return L10n.text("member.module.daily_health.title", fallback: "日常健康")
//        }
//    }
//
//    private func moduleSubtitle(_ module: MaintenanceModule) -> String {
//        switch module {
//        case .medical:
//            return L10n.text("member.module.medical.subtitle", fallback: "慢病、用药、体检、症状随访")
//        case .nutrition:
//            return L10n.text("member.module.nutrition.subtitle", fallback: "饮食目标、营养、体重管理")
//        case .dailyHealth:
//            return L10n.text("member.module.daily_health.subtitle", fallback: "运动、睡眠、饮水、照护提醒（预留）")
//        }
//    }
//
//    private func sheet(for module: MaintenanceModule) -> ModuleSheet {
//        switch module {
//        case .medical:
//            return .medical
//        case .nutrition:
//            return .nutrition
//        case .dailyHealth:
//            return .medical
//        }
//    }
//
//    private func createMemberAndEnterModules() async {
//        guard canAdvanceFromRelationship, !isSavingMember else { return }
//        isSavingMember = true
//        defer { isSavingMember = false }
//        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
//        let member = await store.addMember(
//            name: trimmedName,
//            relationship: relationshipCode,
//            gender: gender,
//            birthDate: birthDate
//        )
//        guard let member else {
//            alertMessage = L10n.text("home.members.add.failed")
//            return
//        }
//        createdMember = member
//        step = .modules
//    }
//
//    private func persistModuleSelection(
//        module: MaintenanceModule,
//        isCompleted: Bool,
//        summaryText: String
//    ) async {
//        guard let createdMember else { return }
//        await persistModuleSelection(memberID: createdMember.id, module: module, isCompleted: isCompleted, summaryText: summaryText)
//    }
//
//    private func persistModuleSelection(
//        memberID: Int,
//        module: MaintenanceModule,
//        isCompleted: Bool,
//        summaryText: String
//    ) async {
//        do {
//            _ = try await homeDependencies.memberModuleSetupUseCase.saveModuleSetting(
//                memberID: memberID,
//                moduleCode: module.rawValue,
//                isEnabled: selectedModules.contains(module),
//                isCompleted: isCompleted,
//                displayOrder: module.displayOrder,
//                summaryText: summaryText,
//                detailData: ["module_code": module.rawValue, "selected": selectedModules.contains(module) ? "true" : "false"],
//                completedAt: isCompleted ? Date() : nil
//            )
//        } catch {
//            alertMessage = error.localizedDescription
//        }
//    }
//
//    private func finish() async {
//        guard canFinish else { return }
//        isPersistingModules = true
//        defer { isPersistingModules = false }
//        dismiss()
//    }
//
//    private func memberSummaryCard(member: Member) -> some View {
//        VStack(alignment: .leading, spacing: 6) {
//            Text(member.name)
//                .font(.headline)
//            Text(member.relationship)
//                .font(.footnote)
//                .foregroundStyle(.secondary)
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding(14)
//        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//    }
//
//    private var formattedBirthDate: String {
//        guard let birthDate else { return L10n.text("home.members.field.birth_date_placeholder") }
//        return birthDate.formatted(date: .long, time: .omitted)
//    }
//
//    private func fieldTitle(_ title: String, required: Bool) -> some View {
//        HStack(spacing: 4) {
//            Text(title)
//                .font(.headline.weight(.semibold))
//            if required {
//                Text("*")
//                    .font(.headline.weight(.semibold))
//                    .foregroundStyle(Color(uiColor: .systemRed))
//            }
//        }
//    }
//
//    private func relationshipChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
//        Button(action: action) {
//            Text(title)
//                .font(.subheadline.weight(.semibold))
//                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
//                .frame(maxWidth: .infinity)
//                .padding(.vertical, 10)
//                .background(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
//                )
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
//                )
//        }
//        .buttonStyle(.plain)
//    }
//
//    private func genderChip(title: String, value: String) -> some View {
//        Button {
//            gender = value
//            triggerHaptic(style: .light)
//        } label: {
//            HStack(spacing: 8) {
//                Image(systemName: gender == value ? "record.circle.fill" : "circle")
//                    .symbolRenderingMode(.hierarchical)
//                Text(title)
//            }
//            .foregroundStyle(gender == value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
//            .padding(.vertical, 10)
//            .padding(.horizontal, 12)
//            .frame(maxWidth: .infinity)
//            .background(
//                RoundedRectangle(cornerRadius: 12, style: .continuous)
//                    .fill(gender == value ? Color.accentColor.opacity(0.12) : Color.clear)
//            )
//        }
//        .buttonStyle(.plain)
//    }
//
//    private func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
//#if canImport(UIKit)
//        UIImpactFeedbackGenerator(style: style).impactOccurred()
//#endif
//    }
//
//}
//
//private extension MemberCreationStepperView.MaintenanceModule {
//    var displayOrder: Int {
//        switch self {
//        case .medical:
//            return 0
//        case .nutrition:
//            return 1
//        case .dailyHealth:
//            return 2
//        }
//    }
//}
//
//private struct MemberMedicalSetupSheet: View {
//    @Environment(\.dismiss) private var dismiss
//    let member: Member?
//    let setupUseCase: MemberModuleSetupUseCase
//    let onSaved: (String) -> Void
//
//    @State private var selectedChronicConditions: Set<String> = []
//    @State private var longTermMedications = ""
//    @State private var medicationNotes = ""
//    @State private var examFocus: Set<String> = []
//    @State private var symptomFocus = ""
//    @State private var notes = ""
//    @State private var isSaving = false
//    @State private var alertMessage: String?
//
//    private let chronicOptions = ["糖尿病", "高血压", "高血脂", "痛风", "脂肪肝", "肾病", "其他"]
//    private let examOptions = ["血糖", "血脂", "尿酸", "肝肾功能", "血压", "体重"]
//
//    var body: some View {
//        CompatibleNavigationContainer {
//            ScrollView {
//                VStack(alignment: .leading, spacing: 16) {
//                    chipSection(title: "慢病档案", options: chronicOptions, selected: $selectedChronicConditions)
//                    textSection(title: "长期用药", placeholder: "例如二甲双胍、降压药", text: $longTermMedications)
//                    textSection(title: "用药说明", placeholder: "用药提醒、忌口或服药说明", text: $medicationNotes)
//                    chipSection(title: "体检关注指标", options: examOptions, selected: $examFocus)
//                    textSection(title: "症状/随访关注项", placeholder: "例如胃肠不适、浮肿、血压波动", text: $symptomFocus)
//                    textSection(title: "补充说明", placeholder: "其他医疗模块补充信息", text: $notes)
//                }
//                .padding(16)
//            }
//            .navigationTitle("医疗模块")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("取消") { dismiss() }
//                }
//            }
//            .safeAreaInset(edge: .bottom) {
//                Button {
//                    Task { await save() }
//                } label: {
//                    HStack {
//                        Spacer()
//                        if isSaving { ProgressView().tint(.white) } else { Text("保存").font(.headline.weight(.semibold)).foregroundStyle(.white) }
//                        Spacer()
//                    }
//                    .padding(.vertical, 14)
//                    .background(Color.accentColor)
//                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                }
//                .buttonStyle(.plain)
//                .padding(16)
//            }
//            .alert("保存失败", isPresented: Binding(
//                get: { alertMessage != nil },
//                set: { if !$0 { alertMessage = nil } }
//            )) {
//                Button("知道了", role: .cancel) {}
//            } message: {
//                Text(alertMessage ?? "")
//            }
//        }
//    }
//
//    private func save() async {
//        guard let member else { return }
//        guard isSaving == false else { return }
//        isSaving = true
//        defer { isSaving = false }
//        do {
//            let summary = selectedChronicConditions.isEmpty ? "医疗模块已完善" : selectedChronicConditions.sorted().joined(separator: "、")
//            _ = try await setupUseCase.saveMedicalProfile(
//                memberID: member.id,
//                chronicConditions: Array(selectedChronicConditions),
//                longTermMedications: longTermMedications.split(separator: "、").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
//                medicationNotes: medicationNotes,
//                examFocus: Array(examFocus),
//                symptomFollowUpFocus: symptomFocus.split(separator: "、").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
//                notes: notes
//            )
//            onSaved(summary)
//            dismiss()
//        } catch {
//            alertMessage = error.localizedDescription
//        }
//    }
//
//    private func chipSection(title: String, options: [String], selected: Binding<Set<String>>) -> some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text(title).font(.headline.weight(.semibold))
//            FlowLayout(items: options, spacing: 8) { option in
//                let isSelected = selected.wrappedValue.contains(option)
//                Button {
//                    if isSelected {
//                        selected.wrappedValue.remove(option)
//                    } else {
//                        selected.wrappedValue.insert(option)
//                    }
//                } label: {
//                    Text(option)
//                        .font(.subheadline.weight(.semibold))
//                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
//                        .padding(.horizontal, 12)
//                        .padding(.vertical, 8)
//                        .background(
//                            Capsule(style: .continuous)
//                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
//                        )
//                }
//                .buttonStyle(.plain)
//            }
//        }
//    }
//
//    private func textSection(title: String, placeholder: String, text: Binding<String>) -> some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text(title).font(.headline.weight(.semibold))
//            TextEditor(text: text)
//                .frame(minHeight: 88)
//                .padding(8)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
//                )
//                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
//        }
//    }
//
//}
//
//private struct DatePickerSheet: View {
//    @Binding var selectedDate: Date?
//    let datePickerSheetHeight: CGFloat
//
//    @State private var tempDate: Date
//
//    init(selectedDate: Binding<Date?>, datePickerSheetHeight: CGFloat) {
//        self._selectedDate = selectedDate
//        self.datePickerSheetHeight = datePickerSheetHeight
//        self._tempDate = State(initialValue: selectedDate.wrappedValue ?? Calendar.current.date(byAdding: .year, value: -24, to: Date()) ?? Date())
//    }
//
//    var body: some View {
//        AdaptiveSheetContainer.fixed(
//            height: datePickerSheetHeight,
//            cancelTitle: L10n.text("common.cancel"),
//            confirmTitle: L10n.text("common.done"),
//            cancelColor: .secondary,
//            confirmColor: .accentColor,
//            onCancel: {},
//            onConfirm: {
//                selectedDate = tempDate
//            }
//        ) {
//            DatePicker(
//                L10n.text("home.members.field.birth_date"),
//                selection: $tempDate,
//                in: ...Date(),
//                displayedComponents: .date
//            )
//            .datePickerStyle(.wheel)
//            .labelsHidden()
//            .frame(maxWidth: .infinity, alignment: .center)
//        }
//    }
//}
//
//private struct MemberNutritionSetupSheet: View {
//    @Environment(\.dismiss) private var dismiss
//    let member: Member?
//    let goalUseCase: NutritionGoalUseCase
//    let setupUseCase: MemberModuleSetupUseCase
//    let onSaved: (String) -> Void
//
//    @State private var goalType: String = "maintain"
//    @State private var dailyEnergyTargetKcal = ""
//    @State private var carbohydrateTargetG = ""
//    @State private var proteinTargetG = ""
//    @State private var fatTargetG = ""
//    @State private var mealDistribution: [String: Double] = [
//        "breakfast": 0.3,
//        "lunch": 0.4,
//        "dinner": 0.25,
//        "snack": 0.05
//    ]
//    @State private var isLoadingDefaults = true
//    @State private var isSaving = false
//    @State private var alertMessage: String?
//
//    var body: some View {
//        CompatibleNavigationContainer {
//            Form {
//                Section("目标模式") {
//                    Picker("目标模式", selection: $goalType) {
//                        Text("减重").tag("lose_weight")
//                        Text("保持体重").tag("maintain")
//                        Text("打造肌肉").tag("gain_muscle")
//                        Text("自定义").tag("custom")
//                    }
//                    .pickerStyle(.segmented)
//                }
//
//                Section("能量目标") {
//                    TextField("每日卡路里目标", text: $dailyEnergyTargetKcal)
//                        .keyboardType(.decimalPad)
//                }
//
//                Section("营养目标") {
//                    TextField("碳水化合物 (g)", text: $carbohydrateTargetG).keyboardType(.decimalPad)
//                    TextField("蛋白质 (g)", text: $proteinTargetG).keyboardType(.decimalPad)
//                    TextField("脂肪 (g)", text: $fatTargetG).keyboardType(.decimalPad)
//                }
//
//                Section("餐次目标") {
//                    mealRow(title: "早餐", key: "breakfast")
//                    mealRow(title: "午餐", key: "lunch")
//                    mealRow(title: "晚餐", key: "dinner")
//                    mealRow(title: "小吃", key: "snack")
//                }
//
//                if isLoadingDefaults {
//                    Section {
//                        ProgressView()
//                    }
//                }
//            }
//            .navigationTitle("饮食健康")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("取消") { dismiss() }
//                }
//            }
//            .safeAreaInset(edge: .bottom) {
//                Button {
//                    Task { await save() }
//                } label: {
//                    HStack {
//                        Spacer()
//                        if isSaving { ProgressView().tint(.white) } else { Text("保存").font(.headline.weight(.semibold)).foregroundStyle(.white) }
//                        Spacer()
//                    }
//                    .padding(.vertical, 14)
//                    .background(Color.accentColor)
//                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
//                }
//                .buttonStyle(.plain)
//                .padding(16)
//            }
//            .task {
//                await loadDefaults()
//            }
//            .alert("保存失败", isPresented: Binding(
//                get: { alertMessage != nil },
//                set: { if !$0 { alertMessage = nil } }
//            )) {
//                Button("知道了", role: .cancel) {}
//            } message: {
//                Text(alertMessage ?? "")
//            }
//        }
//    }
//
//    private func loadDefaults() async {
//        guard let member else {
//            isLoadingDefaults = false
//            return
//        }
//        do {
//            let state = try await goalUseCase.loadGoalState(memberID: member.id)
//            let defaults = state.defaults
//            if let goal = state.goal {
//                goalType = goal.goalType
//                dailyEnergyTargetKcal = goal.dailyEnergyTargetKcal.map { String(format: "%.0f", $0) } ?? String(format: "%.0f", defaults.energyKcal)
//                carbohydrateTargetG = goal.carbohydrateTargetG.map { String(format: "%.0f", $0) } ?? String(format: "%.0f", defaults.carbohydrateG)
//                proteinTargetG = goal.proteinTargetG.map { String(format: "%.0f", $0) } ?? String(format: "%.0f", defaults.proteinG)
//                fatTargetG = goal.fatTargetG.map { String(format: "%.0f", $0) } ?? String(format: "%.0f", defaults.fatG)
//                mealDistribution = goal.mealDistribution.merging(
//                    ["breakfast": 0.3, "lunch": 0.4, "dinner": 0.25, "snack": 0.05],
//                    uniquingKeysWith: { current, _ in current }
//                )
//            } else {
//                dailyEnergyTargetKcal = String(format: "%.0f", defaults.energyKcal)
//                carbohydrateTargetG = String(format: "%.0f", defaults.carbohydrateG)
//                proteinTargetG = String(format: "%.0f", defaults.proteinG)
//                fatTargetG = String(format: "%.0f", defaults.fatG)
//            }
//        } catch {
//            alertMessage = error.localizedDescription
//        }
//        isLoadingDefaults = false
//    }
//
//    private func save() async {
//        guard let member else { return }
//        guard isSaving == false else { return }
//        isSaving = true
//        defer { isSaving = false }
//        do {
//            let saved = try await goalUseCase.saveGoal(
//                memberID: member.id,
//                goalType: goalType,
//                dailyEnergyTargetKcal: Double(dailyEnergyTargetKcal),
//                carbohydrateTargetG: Double(carbohydrateTargetG),
//                proteinTargetG: Double(proteinTargetG),
//                fatTargetG: Double(fatTargetG),
//                mealDistribution: mealDistribution
//            )
//            let summary = "卡路里 \(Int(saved.dailyEnergyTargetKcal ?? 0))"
//            _ = try await setupUseCase.saveModuleSetting(
//                memberID: member.id,
//                moduleCode: "nutrition",
//                isEnabled: true,
//                isCompleted: true,
//                displayOrder: 1,
//                summaryText: summary,
//                detailData: [
//                    "goal_type": goalType,
//                    "daily_energy_target_kcal": "\(dailyEnergyTargetKcal)",
//                    "carbohydrate_target_g": "\(carbohydrateTargetG)",
//                    "protein_target_g": "\(proteinTargetG)",
//                    "fat_target_g": "\(fatTargetG)"
//                ],
//                completedAt: Date()
//            )
//            onSaved(summary)
//            dismiss()
//        } catch {
//            alertMessage = error.localizedDescription
//        }
//    }
//
//    private func mealRow(title: String, key: String) -> some View {
//        HStack {
//            Text(title)
//            Spacer()
//            Text(percentText(for: key))
//                .foregroundStyle(.secondary)
//        }
//    }
//
//    private func percentText(for key: String) -> String {
//        let percent = Int((mealDistribution[key] ?? 0) * 100)
//        return "\(percent)%"
//    }
//}
//
//private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
//    let items: Data
//    let spacing: CGFloat
//    let content: (Data.Element) -> Content
//
//    init(items: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
//        self.items = items
//        self.spacing = spacing
//        self.content = content
//    }
//
//    var body: some View {
//        // 简化版横向换行布局：利用水平滚动避免过度复杂的自定义布局
//        ScrollView(.horizontal, showsIndicators: false) {
//            HStack(spacing: spacing) {
//                ForEach(Array(items), id: \.self) { item in
//                    content(item)
//                }
//            }
//        }
//    }
//}
