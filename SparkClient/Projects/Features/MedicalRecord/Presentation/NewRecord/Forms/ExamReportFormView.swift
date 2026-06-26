import SwiftUI

/// 医疗检查报告草稿：支持新建、服务端编辑与本地编辑；子项通过 `AddLabItemSheet` 维护。
struct ExamReportFormView: View {
    enum Mode {
        case create(CreateContext)
        case serverEdit(existing: SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments)
        case localEdit(existing: MedicalReportRecognitionDraft, onSubmit: (MedicalReportRecognitionDraft) -> Void)
    }

    struct CreateContext {
        let memberID: Int
        let medicalCaseID: Int?
        let submissionService: MedicalRecordFormSubmissionService
        let onCreated: ((Int, MedicalReportRecognitionDraft) -> Void)?

        init(
            memberID: Int,
            medicalCaseID: Int? = nil,
            submissionService: MedicalRecordFormSubmissionService,
            onCreated: ((Int, MedicalReportRecognitionDraft) -> Void)? = nil
        ) {
            self.memberID = memberID
            self.medicalCaseID = medicalCaseID
            self.submissionService = submissionService
            self.onCreated = onCreated
        }
    }

    struct ItemDraft: Identifiable, Equatable {
        var id: UUID
        var category: String
        var subCategory: String
        var itemName: String
        var resultValue: String
        var unit: String
        var referenceRange: String
        var flag: String
        /// 影像 / 病理等：`MedicalReportItem.modality`
        var modality: String
        /// `MedicalReportItem.bodyPart`
        var bodyPart: String
        /// `MedicalReportItem.resultAt`（检查或报告日期）
        var resultAt: String
        /// `MedicalReportItem.diagnosis`（所见+结论等长文本）
        var diagnosis: String

        init(
            id: UUID = UUID(),
            category: String = "",
            subCategory: String = "",
            itemName: String = "",
            resultValue: String = "",
            unit: String = "",
            referenceRange: String = "",
            flag: String = "",
            modality: String = "",
            bodyPart: String = "",
            resultAt: String = "",
            diagnosis: String = ""
        ) {
            self.id = id
            self.category = category
            self.subCategory = subCategory
            self.itemName = itemName
            self.resultValue = resultValue
            self.unit = unit
            self.referenceRange = referenceRange
            self.flag = flag
            self.modality = modality
            self.bodyPart = bodyPart
            self.resultAt = resultAt
            self.diagnosis = diagnosis
        }
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let submissionService: MedicalRecordFormSubmissionService?
    let onReportDraftSaved: ((MedicalReportRecognitionDraft) -> Void)?

    @State private var pageType: ExaminationReportCategory
    @State private var category: String
    @State private var title: String
    @State private var hospital: String
    @State private var doctor: String
    @State private var content: String
    @State private var date: String
    @State private var examDay: Date
    @State private var formKeyboardVisible = false
    /// 检验模块：新建子项时的默认一级/二级分类（仅存于 UI，写入各 `ItemDraft`）。
    @State private var labPrimaryCategory: String
    @State private var labSubCategory: String
    @State private var items: [ItemDraft]
    @State private var editingItem: ItemDraft?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let formLog: Logger = ConsoleLogger()
    private let formLogModule: LogModule = .medical

    init(
        mode: Mode,
        submissionService: MedicalRecordFormSubmissionService? = nil,
        onReportDraftSaved: ((MedicalReportRecognitionDraft) -> Void)? = nil
    ) {
        self.mode = mode
        self.submissionService = submissionService
        self.onReportDraftSaved = onReportDraftSaved

        let seed: MedicalReportRecognitionDraft
        switch mode {
        case .create:
            seed = .init(category: "laboratory", title: "", hospital: "", doctor: "", content: "", date: "", details: [])
        case .serverEdit(let existing):
            seed = MedicalCaseTimelineRemoteMapping.examinationDraft(from: existing)
        case .localEdit(let existing, _):
            seed = existing
        }

        let pageType = ExaminationReportCategory.from(seed.category)
        _pageType = State(initialValue: pageType)
        _category = State(initialValue: seed.category ?? pageType.rawValue)
        _title = State(initialValue: seed.title)
        _hospital = State(initialValue: seed.hospital ?? "")
        _doctor = State(initialValue: seed.doctor ?? "")
        _content = State(initialValue: seed.content ?? "")
        let rawDate = (seed.date ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDate = rawDate.isEmpty ? Self.formatExamDayString(Date()) : rawDate
        _date = State(initialValue: resolvedDate)
        _examDay = State(initialValue: Self.parseExamDay(from: resolvedDate))
        let labSeed = pageType == .laboratory ? seed.details.first : nil
        _labPrimaryCategory = State(initialValue: labSeed?.category ?? "")
        _labSubCategory = State(initialValue: labSeed?.subCategory ?? "")
        _items = State(initialValue: seed.details.map {
            ItemDraft(
                category: $0.category,
                subCategory: $0.subCategory ?? "",
                itemName: $0.itemName ?? "",
                resultValue: $0.resultValue ?? "",
                unit: $0.unit ?? "",
                referenceRange: $0.referenceRange ?? "",
                flag: $0.flag ?? "",
                modality: $0.modality ?? "",
                bodyPart: $0.bodyPart ?? "",
                resultAt: $0.resultAt ?? "",
                diagnosis: $0.diagnosis ?? ""
            )
        })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(
                    title: L10n.text("medical_record.forms.medical_case.section.basic"),
                    titleSystemImage: "calendar"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("medical_record.forms.exam_report.field.exam_date"))
                                .font(.subheadline.weight(.medium))
                            DatePicker(
                                "",
                                selection: $examDay,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .onChange(of: examDay) { newValue in
                                date = Self.formatExamDayString(newValue)
                            }
                        }

                        VisitDivider(color: Color(.separator), height: 1, verticalPadding: 6)

                        SparkFormTextRow(
                            title: L10n.text("medical_record.forms.field.report_title"),
                            text: $title,
                            placeholder: L10n.text("medical_record.forms.exam_report.placeholder.report_title"),
                            required: true,
                            keyboardVisible: $formKeyboardVisible
                        )

                        SparkFormCard(title: L10n.text("medical_record.forms.exam_report.field.exam_type")) {
                            VStack(alignment: .leading, spacing: 18) {
                                Picker(
                                    L10n.text("medical_record.forms.exam_report.field.exam_type"),
                                    selection: $pageType
                                ) {
                                    ForEach(ExaminationReportCategory.allCases, id: \.self) { type in
                                        Label(
                                            L10n.text(type.titleKey),
                                            systemImage: type.icon
                                        )
                                        .tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: pageType) { newValue in
                                    category = newValue.rawValue
                                }

                                examTypeModuleContent
                            }
                        }

                        SparkFormTextRow(
                            title: L10n.text("medical_record.forms.exam_report.field.hospital"),
                            text: $hospital,
                            placeholder: L10n.text("medical_record.forms.exam_report.placeholder.hospital"),
                            keyboardVisible: $formKeyboardVisible
                        )
                        SparkFormTextRow(
                            title: L10n.text("medical_record.forms.exam_report.field.exam_doctor"),
                            text: $doctor,
                            placeholder: L10n.text("medical_record.forms.exam_report.placeholder.doctor"),
                            keyboardVisible: $formKeyboardVisible
                        )

                        VisitDivider(color: Color(.separator), height: 1, verticalPadding: 6)

                        SparkFormTextAreaRow(
                            title: L10n.text("medical_record.forms.field.report_content"),
                            text: $content,
                            placeholder: L10n.text("medical_record.forms.exam_report.placeholder.report_content"),
                            keyboardVisible: $formKeyboardVisible
                        )
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
            .padding(16)
        }
        .sparkKeyboardDoneToolbar {
            SparkKeyboardDismiss.endEditing()
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .sparkFormBottomBar(
            canSubmit: !isSaving,
            saveTitle: saveTitle,
            keyboardVisible: $formKeyboardVisible,
            onCancel: {
                formLog.info("ExamReportFormView: cancel tapped mode=\(modeLogLabel)", module: formLogModule)
                dismiss()
            },
            onSave: { Task { await saveNow() } }
        )
        .sheet(item: $editingItem) { item in
            Group {
                switch pageType {
                case .laboratory:
                    AddLabItemSheet(draft: item) { newItem in
                        mergeEditedItem(newItem, replacing: item.id)
                    }
                case .imaging:
                    AddImagingReportItemSheet(draft: item) { newItem in
                        mergeEditedItem(newItem, replacing: item.id)
                    }
                case .pathology:
                    AddPathologyReportItemSheet(draft: item) { newItem in
                        mergeEditedItem(newItem, replacing: item.id)
                    }
                }
            }
        }
        .alert(L10n.text("medical_record.forms.error.submit_failed"), isPresented: Binding(get: { errorMessage != nil }, set: { if $0 == false { errorMessage = nil } })) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 检查类型内模块（对齐 Health：Picker 下方按类型展开；数据仍用 `items` / `MedicalReportItem`）

    @ViewBuilder
    private var examTypeModuleContent: some View {
        switch pageType {
        case .laboratory:
            laboratoryModule
        case .imaging:
            imagingPathologyItemsModule(isPathology: false)
        case .pathology:
            imagingPathologyItemsModule(isPathology: true)
        }
    }

    private var laboratoryModule: some View {
        VStack(alignment: .leading, spacing: 16) {
            SparkLabExamCategoryCascadeRow(
                primaryTitle: L10n.text("medical_record.forms.exam_report.lab.primary_category"),
                secondaryTitle: L10n.text("medical_record.forms.exam_report.lab.subcategory"),
                primaryPlaceholder: L10n.text("medical_record.forms.exam_report.lab.placeholder.primary"),
                secondaryPlaceholder: L10n.text("medical_record.forms.exam_report.lab.placeholder.subcategory"),
                primaryRequired: true,
                secondaryRequired: false,
                primary: $labPrimaryCategory,
                secondary: $labSubCategory,
                keyboardVisible: $formKeyboardVisible
            )
            Button {
                presentNewLabItem()
            } label: {
                Label(L10n.text("medical_record.forms.exam_report.add_item"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)

            if items.isEmpty {
                laboratoryEmptyState
            }
            itemChipList
        }
    }

    private func imagingPathologyItemsModule(isPathology: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                presentNewGenericItem()
            } label: {
                Label(L10n.text("medical_record.forms.exam_report.add_item"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)

            if items.isEmpty {
                imagingPathologyEmptyState(isPathology: isPathology)
            }
            itemChipList
        }
    }

    private var laboratoryEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mail.and.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.gray.opacity(0.35))
            Text(L10n.text("medical_record.forms.exam_report.items.empty.lab.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(L10n.text("medical_record.forms.exam_report.items.empty.lab.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func imagingPathologyEmptyState(isPathology: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: isPathology ? "microscope" : "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.gray.opacity(0.35))
            Text(L10n.text(isPathology
                ? "medical_record.forms.exam_report.items.empty.pathology.title"
                : "medical_record.forms.exam_report.items.empty.imaging.title"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(L10n.text(isPathology
                ? "medical_record.forms.exam_report.items.empty.pathology.subtitle"
                : "medical_record.forms.exam_report.items.empty.imaging.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var itemChipList: some View {
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.itemName.isEmpty ? L10n.text("medical_record.forms.exam_report.unnamed_item") : item.itemName)
                    .font(.subheadline.weight(.semibold))
                Text(chipSubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
            .onTapGesture { editingItem = item }
        }
    }

    private func presentNewLabItem() {
        editingItem = ItemDraft(
            category: labPrimaryCategory,
            subCategory: labSubCategory,
            itemName: "",
            resultValue: "",
            unit: "",
            referenceRange: "",
            flag: ""
        )
    }

    private func presentNewGenericItem() {
        editingItem = ItemDraft()
    }

    private func chipSubtitle(for item: ItemDraft) -> String {
        switch pageType {
        case .laboratory:
            return L10n.format("medical_record.forms.exam_report.result_line", item.resultValue)
        case .imaging, .pathology:
            let diag = item.diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
            if diag.isEmpty == false {
                return diag.count > 80 ? String(diag.prefix(80)) + "…" : diag
            }
            let part = item.bodyPart.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.isEmpty == false { return part }
            return item.resultValue.isEmpty ? "—" : item.resultValue
        }
    }

    private func mergeEditedItem(_ newItem: ItemDraft, replacing id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index] = newItem
        } else {
            items.append(newItem)
        }
    }

    private var modeLogLabel: String {
        switch mode {
        case .create: return "create"
        case .serverEdit: return "serverEdit"
        case .localEdit: return "localEdit"
        }
    }

    private var navTitle: String {
        switch mode {
        case .create: return L10n.text("medical_record.forms.exam_report.title.create")
        case .serverEdit: return L10n.text("medical_record.forms.exam_report.title.edit")
        case .localEdit: return L10n.text("medical_record.forms.exam_report.title.edit_local")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return L10n.text("common.save")
        case .serverEdit: return L10n.text("medical_record.forms.action.update")
        case .localEdit: return L10n.text("common.done")
        }
    }

    @MainActor
    private func saveNow() async {
        formLog.info("ExamReportFormView: save started mode=\(modeLogLabel) items=\(items.count)", module: formLogModule)

        let details = items.enumerated().map { index, row in
            MedicalReportItem(
                category: row.category.nilIfBlank ?? category,
                subCategory: row.subCategory.nilIfBlank,
                itemName: row.itemName.nilIfBlank,
                itemCode: nil,
                resultValue: row.resultValue.nilIfBlank,
                unit: row.unit.nilIfBlank,
                referenceRange: row.referenceRange.nilIfBlank,
                flag: row.flag.nilIfBlank,
                resultAt: row.resultAt.nilIfBlank,
                modality: row.modality.nilIfBlank,
                bodyPart: row.bodyPart.nilIfBlank,
                diagnosis: row.diagnosis.nilIfBlank,
                extra: nil,
                sortOrder: "\(index)"
            )
        }
        let draft = MedicalReportRecognitionDraft(
            category: category.nilIfBlank ?? pageType.rawValue,
            title: title,
            hospital: hospital.nilIfBlank,
            doctor: doctor.nilIfBlank,
            content: content,
            date: date.nilIfBlank,
            details: details
        )

        switch mode {
        case .localEdit(_, let onSubmit):
            onSubmit(draft)
            formLog.info("ExamReportFormView: local submit finished", module: formLogModule)
            dismiss()

        case .serverEdit(let existing):
            guard let submissionService else {
                formLog.warning("ExamReportFormView: server submit config missing", module: formLogModule)
                errorMessage = L10n.text("medical_record.forms.error.submit_failed")
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                try await submissionService.submitMedicalReportUpdate(report: existing, draft: draft)
                onReportDraftSaved?(draft)
                formLog.info("ExamReportFormView: server save succeeded", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("ExamReportFormView: server save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }

        case .create(let context):
            isSaving = true
            defer { isSaving = false }
            do {
                let newID = try await context.submissionService.submitMedicalReportCreate(
                    memberID: context.memberID,
                    draft: draft,
                    medicalCaseID: context.medicalCaseID
                )
                context.onCreated?(newID, draft)
                formLog.info("ExamReportFormView: create save succeeded id=\(newID)", module: formLogModule)
                dismiss()
            } catch {
                formLog.error("ExamReportFormView: create save failed \(error.localizedDescription)", module: formLogModule)
                errorMessage = error.localizedDescription
            }
        }
    }

    private static let examDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseExamDay(from raw: String?) -> Date {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return Date()
        }
        if let parsed = examDayFormatter.date(from: raw) {
            return parsed
        }
        return ISO8601DateFormatter().date(from: raw) ?? Date()
    }

    private static func formatExamDayString(_ day: Date) -> String {
        examDayFormatter.string(from: day)
    }
}
