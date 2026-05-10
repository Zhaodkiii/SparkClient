import SwiftUI
import UIKit
import PDFKit

import Foundation

///
/// 病历表单草稿（本地/云端暂存）
/// 用途：
/// 1. AI 问诊过程中自动填充的病历信息
/// 2. 用户未提交前保存的草稿
/// 3. 编辑已有病历
/// 4. 上传到服务器前的临时数据结构
///
struct MedicalCaseFormDraft: Equatable, Sendable {
    /// 草稿ID（nil = 新建）
    var id: Int?
    
    /// 成员ID（家庭成员/用户ID）
    var memberID: Int
    
    /// 记录类型：门诊(outpatient)/住院(inhospital)/体检(physical)
    var recordType: String
    
    /// 状态：1=草稿 2=已提交 3=已作废
    var status: Int
    
    /// 病历标题（如：感冒就诊、体检报告、胃炎复查）
    var title: String
    
    /// 医院名称
    var hospitalName: String
    
    /// 诊断总结（医生结论）
    var diagnosisSummary: String
    
    /// 就诊日期
    var visitDate: Date
    
    /// 现病史（当前哪里不舒服、症状、持续时间）
    var presentIllness: String
    
    /// 既往史（过敏、既往疾病、手术、慢性病）
    var pastHistory: String
    
    /// 备注/补充信息
    var notes: String
    
    /// 就诊时年龄（自动计算）
    var ageAtVisit: Int?

    /// 严重程度（low/medium/high），可为空
    var severity: String?

    /// 展示状态（治疗中/已治愈等），可为空
    var caseStatus: String?
    
    /// 扩展字段（灵活存储额外信息）
    var extra: [String: String]

    /// 初始化（提供默认值，方便新建）
    init(
        id: Int? = nil,
        memberID: Int,
        recordType: String = "outpatient",
        status: Int = 1,
        title: String = "",
        hospitalName: String = "",
        diagnosisSummary: String = "",
        visitDate: Date = Date(),
        presentIllness: String = "",
        pastHistory: String = "",
        notes: String = "",
        ageAtVisit: Int? = nil,
        severity: String? = nil,
        caseStatus: String? = nil,
        extra: [String: String] = [:]
    ) {
        self.id = id
        self.memberID = memberID
        self.recordType = recordType
        self.status = status
        self.title = title
        self.hospitalName = hospitalName
        self.diagnosisSummary = diagnosisSummary
        self.visitDate = visitDate
        self.presentIllness = presentIllness
        self.pastHistory = pastHistory
        self.notes = notes
        self.ageAtVisit = ageAtVisit
        self.severity = severity
        self.caseStatus = caseStatus
        self.extra = extra
    }
}

extension MedicalCaseFormDraft {
    init(item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        let extra = item.extra ?? [:]
        self.init(
            id: item.id,
            memberID: item.member,
            recordType: item.recordType?.nilIfBlank ?? "outpatient",
            status: item.status ?? 1,
            title: item.title ?? "",
            hospitalName: item.hospitalName ?? "",
            diagnosisSummary: item.diagnosisSummary ?? "",
            visitDate: Self.decodeVisitDate(from: extra) ?? item.updatedAt ?? item.createdAt ?? Date(),
            presentIllness: extra["present_illness"] ?? "",
            pastHistory: extra["past_history"] ?? "",
            notes: extra["notes"] ?? "",
            ageAtVisit: item.ageAtVisit,
            severity: item.severity?.nilIfBlank,
            caseStatus: MedicalCaseFormOptionCatalog.normalizedStatusValue(item.caseStatus),
            extra: extra
        )
    }

    var encodedExtra: [String: String] {
        var result = extra
        result["visit_date"] = MedicalDateCoding.encodeDateOnly(visitDate)
        result["present_illness"] = presentIllness.nilIfBlank
        result["past_history"] = pastHistory.nilIfBlank
        result["notes"] = notes.nilIfBlank
        return result
    }

    func makeLocalSummary(existing: SparkMedicalSyncAPI.RemoteMedicalCaseSummary? = nil, id fallbackID: Int? = nil) -> SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
        SparkMedicalSyncAPI.RemoteMedicalCaseSummary(
            id: id ?? existing?.id ?? fallbackID ?? Int(Date().timeIntervalSince1970),
            member: memberID,
            recordType: recordType,
            status: status,
            title: title,
            hospitalName: hospitalName.nilIfBlank,
            ageAtVisit: ageAtVisit,
            severity: severity?.nilIfBlank,
            caseStatus: MedicalCaseFormOptionCatalog.normalizedStatusValue(caseStatus),
            diagnosisSummary: diagnosisSummary.nilIfBlank,
            extra: encodedExtra,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(),
            symptoms: existing?.symptoms,
            medications: existing?.medications,
            attachments: existing?.attachments
        )
    }

    private static func decodeVisitDate(from extra: [String: String]) -> Date? {
        guard let raw = extra["visit_date"], raw.isEmpty == false else { return nil }
        return Self.dateOnlyFormatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct MedicalCaseResourcePayload: Encodable, Sendable {
    let member: Int
    let recordType: String
    let status: Int
    let title: String
    let hospitalName: String?
    let ageAtVisit: Int?
    let severity: String?
    let caseStatus: String?
    let diagnosisSummary: String?
    let extra: [String: String]

    enum CodingKeys: String, CodingKey {
        case member
        case recordType = "record_type"
        case status
        case title
        case hospitalName = "hospital_name"
        case ageAtVisit = "age_at_visit"
        case severity
        case caseStatus = "case_status"
        case diagnosisSummary = "diagnosis_summary"
        case extra
    }

    init(draft: MedicalCaseFormDraft) {
        member = draft.memberID
        recordType = draft.recordType
        status = draft.status
        title = draft.title
        hospitalName = draft.hospitalName.nilIfBlank
        ageAtVisit = draft.ageAtVisit
        severity = draft.severity?.nilIfBlank
        caseStatus = MedicalCaseFormOptionCatalog.normalizedStatusValue(draft.caseStatus)
        diagnosisSummary = draft.diagnosisSummary.nilIfBlank
        extra = draft.encodedExtra
    }
}

struct MedicalCaseMutationService {
    let workflowAPI: SparkMedicalWorkflowAPI

    func create(_ draft: MedicalCaseFormDraft) async throws -> SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
        let payload = MedicalCaseResourcePayload(draft: draft)
        return try await workflowAPI.create(
            SparkMedicalSyncAPI.RemoteMedicalCaseSummary.self,
            kind: .cases,
            body: payload
        )
    }

    func update(id: Int, draft: MedicalCaseFormDraft) async throws -> SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
        let payload = MedicalCaseResourcePayload(draft: draft)
        return try await workflowAPI.update(
            SparkMedicalSyncAPI.RemoteMedicalCaseSummary.self,
            kind: .cases,
            id: id,
            body: payload
        )
    }

    func delete(id: Int) async throws {
        try await workflowAPI.delete(kind: .cases, id: id)
    }
}

struct MedicalCaseFormView: View {
    enum Mode {
        case create(memberID: Int, onSaved: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)
        case serverEdit(SparkMedicalSyncAPI.RemoteMedicalCaseSummary, onSaved: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void)
        case localCreate(memberID: Int, onDone: (MedicalCaseFormDraft) -> Void)
        case localEdit(MedicalCaseFormDraft, onDone: (MedicalCaseFormDraft) -> Void)
    }

    @ObservedObject var memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let notificationClient: any NotificationClient
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MedicalCaseFormDraft
    @State private var isSaving = false
    @State private var isKeyboardVisible = false

    init(
        mode: Mode,
        memberContextStore: MemberContextStore,
        workflowAPI: SparkMedicalWorkflowAPI,
        notificationClient: any NotificationClient
    ) {
        self.mode = mode
        self.memberContextStore = memberContextStore
        self.workflowAPI = workflowAPI
        self.notificationClient = notificationClient

        switch mode {
        case .create(let memberID, _), .localCreate(let memberID, _):
            _draft = State(initialValue: MedicalCaseFormDraft(memberID: memberID))
        case .serverEdit(let item, _):
            _draft = State(initialValue: MedicalCaseFormDraft(item: item))
        case .localEdit(let draft, _):
            _draft = State(initialValue: draft)
        }
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SparkFormCard(title: L10n.text("medical_record.forms.medical_case.section.basic", fallback: "基本信息")) {
                        memberPicker
                        DatePicker(L10n.text("medical_record.forms.medical_case.field.visit_date", fallback: "就诊日期"), selection: $draft.visitDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        SparkFormTextRow(
                            title: L10n.text("medical_record.forms.medical_case.field.institution", fallback: "就诊机构"),
                            text: $draft.hospitalName,
                            placeholder: L10n.text("medical_record.forms.medical_case.placeholder.institution", fallback: "医院或诊所名称"),
                            keyboardVisible: $isKeyboardVisible
                        )
                        GridTwo {
                            SeverityPickerRow(
                                title: L10n.text("medical_record.forms.medical_case.field.severity", fallback: "严重程度"),
                                selection: $draft.severity
                            )
                            StatusPickerRow(
                                title: L10n.text("medical_record.forms.medical_case.field.case_status", fallback: "状态"),
                                selection: $draft.caseStatus
                            )
                        }
                    }

                    SparkFormCard(title: L10n.text("medical_record.forms.medical_case.section.content", fallback: "病历内容")) {
                        SparkFormTextAreaRow(
                            title: L10n.text("medical_record.forms.medical_case.field.chief_complaint", fallback: "主诉"),
                            text: $draft.title,
                            minHeight: 88,
                            placeholder: L10n.text("medical_record.forms.medical_case.placeholder.chief_complaint"),
                            required: true,
                            keyboardVisible: $isKeyboardVisible
                        )
                        SparkFormTextAreaRow(
                            title: L10n.text("medical_record.forms.medical_case.field.diagnosis", fallback: "初步诊断"),
                            text: $draft.diagnosisSummary,
                            minHeight: 78,
                            keyboardVisible: $isKeyboardVisible
                        )
                    }
                    VisitDivider(color: Color.black.opacity(0.08))

//                    VStack(alignment: .leading, spacing: 10) {
//
//                    }
                    
                    DisclosureGroup(
                        content: {
                            VStack(spacing: 16) {
                                SparkFormTextAreaRow(
                                    title: L10n.text("medical_record.forms.medical_case.field.present_illness", fallback: "现病史"),
                                    text: $draft.presentIllness,
                                    placeholder: L10n.text("medical_record.forms.medical_case.placeholder.present_illness", fallback: "本次患病以来症状的发生、发展与经过…"),
                                    keyboardVisible: $isKeyboardVisible
                                )
                                SparkFormTextAreaRow(
                                    title: L10n.text("medical_record.forms.medical_case.field.past_history", fallback: "既往史"),
                                    text: $draft.pastHistory,
                                    placeholder: L10n.text("medical_record.forms.medical_case.placeholder.past_history", fallback: "以往疾病/手术/用药等重要病史…"),
                                    keyboardVisible: $isKeyboardVisible
                                )
                                SparkFormTextAreaRow(
                                    title: L10n.text("medical_record.forms.field.notes"),
                                    text: $draft.notes,
                                    placeholder: L10n.text("medical_record.forms.medical_case.placeholder.notes", fallback: "其他说明…"),
                                    keyboardVisible: $isKeyboardVisible
                                )
                            }
                            .padding(6)
                        },
                        label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(L10n.text("medical_record.forms.medical_case.section.history", fallback: "病史"))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .foregroundStyle(Color.gray)
                            }
                        }
                    )
                    .padding(14)
//                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .systemBackground)))
                .padding(16)

            }

            if isSaving {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView(L10n.text("medical_record.forms.medical_case.saving", fallback: "正在保存..."))
                    .padding(16)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel")) { dismiss() }
            }
        }
        .sparkFormBottomBar(
            canSubmit: isSaving == false && isValid,
            saveTitle: saveTitle,
            saveSystemImage: "checkmark",
            keyboardVisible: $isKeyboardVisible,
            onCancel: { dismiss() },
            onSave: { Task { await save() } }
        )
    }

    private var resolvedMemberForDraft: Member? {
        memberContextStore.context.members.first(where: { $0.id == draft.memberID })
    }

    private var memberPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("medical_record.forms.medical_case.field.member_required", fallback: "选择成员 *"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.memberID > 0 {
                MedicalCaseSelectedMemberRow(
                    displayName: resolvedMemberForDraft?.name ?? memberName(for: draft.memberID),
                    relationshipBadge: resolvedMemberForDraft.map { MemberRelationshipCatalog.displayTitle(for: $0.relationship) },
                    subtitle: resolvedMemberForDraft.map { Self.memberAgeGenderSubtitle(for: $0) },
                    onClear: {
                        withAnimation(.snappy) {
                            draft.memberID = 0
                        }
                    }
                )
            } else {
                MemberProfileBindingMenu(
                    memberContextStore: memberContextStore,
                    selectedMemberID: nil,
                    onSelect: { memberID in
                        withAnimation(.snappy) {
                            draft.memberID = memberID ?? 0
                        }
                    }
                ) {
                    HStack(spacing: 8) {
                        Text(L10n.text("medical_record.forms.medical_case.member.placeholder", fallback: "请选择成员"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }

    private static func memberAgeGenderSubtitle(for member: Member) -> String {
        let ageText: String
        if let birth = member.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
            ageText = years > 0 ? "\(years)岁" : "—"
        } else {
            ageText = "—"
        }
        let genderText: String
        switch member.gender {
        case "male":
            genderText = L10n.text("home.members.gender.male")
        case "female":
            genderText = L10n.text("home.members.gender.female")
        default:
            genderText = L10n.text("home.members.gender.unknown")
        }
        return "\(ageText) · \(genderText)"
    }

    private var isValid: Bool {
        draft.memberID > 0 && draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var navigationTitle: String {
        switch mode {
        case .create, .localCreate:
            return L10n.text("medical_record.forms.medical_case.title.create", fallback: "新增病历")
        case .serverEdit, .localEdit:
            return L10n.text("medical_record.forms.medical_case.title.edit", fallback: "编辑病历")
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create, .localCreate:
            return L10n.text("medical_record.forms.medical_case.action.save", fallback: "保存病历")
        case .serverEdit, .localEdit:
            return L10n.text("medical_record.forms.medical_case.action.update", fallback: "更新病历")
        }
    }

    private func memberName(for id: Int) -> String {
        memberContextStore.context.members.first(where: { $0.id == id })?.name
            ?? L10n.text("medical_record.forms.medical_case.member.placeholder", fallback: "请选择成员")
    }

    @MainActor
    private func save() async {
        guard isValid else {
            notificationClient.error(L10n.text("medical_record.forms.medical_case.error.required", fallback: "请完善必填项：成员、主诉"), source: "medical.case.form")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let service = MedicalCaseMutationService(workflowAPI: workflowAPI)
            switch mode {
            case .create(_, let onSaved):
                let saved = try await service.create(draft)
                onSaved(saved)
                notificationClient.success(L10n.text("medical_record.forms.medical_case.toast.saved", fallback: "病历已保存"), source: "medical.case.form")
                dismiss()
            case .serverEdit(let item, let onSaved):
                let saved = try await service.update(id: item.id, draft: draft)
                onSaved(saved)
                notificationClient.success(L10n.text("medical_record.forms.medical_case.toast.updated", fallback: "病历已更新"), source: "medical.case.form")
                dismiss()
            case .localCreate(_, let onDone):
                onDone(draft)
                dismiss()
            case .localEdit(_, let onDone):
                onDone(draft)
                dismiss()
            }
        } catch {
            notificationClient.error(error.localizedDescription, title: L10n.text("medical_record.forms.medical_case.error.save_failed", fallback: "保存失败"), source: "medical.case.form")
        }
    }
}

// MARK: - Severity Picker Row

private struct SeverityPickerRow: View {
    let title: String
    @Binding var selection: String?

    var body: some View {
        OptionalMenuPickerRow(title: title, selection: $selection, options: MedicalCaseFormOptionCatalog.severityOptions)
    }
}

// MARK: - Status Picker Row

private struct StatusPickerRow: View {
    let title: String
    @Binding var selection: String?

    var body: some View {
        OptionalMenuPickerRow(
            title: title,
            selection: Binding(
                get: { MedicalCaseFormOptionCatalog.normalizedStatusValue(selection) },
                set: { selection = $0 }
            ),
            options: MedicalCaseFormOptionCatalog.statusOptions
        )
    }
}

private enum MedicalCaseFormOptionCatalog {
    static var severityOptions: [(value: String, label: String)] {
        [
            ("low", "🙂 \(L10n.text("medical_record.forms.medical_case.severity.low", fallback: "轻度"))"),
            ("medium", "😕 \(L10n.text("medical_record.forms.medical_case.severity.medium", fallback: "中度"))"),
            ("high", "😣 \(L10n.text("medical_record.forms.medical_case.severity.high", fallback: "重度"))"),
        ]
    }

    static var statusOptions: [(value: String, label: String)] {
        [
            ("in_treatment", L10n.text("medical_record.forms.medical_case.status.in_treatment", fallback: "治疗中")),
            ("cured", L10n.text("medical_record.forms.medical_case.status.cured", fallback: "已治愈")),
            ("review", L10n.text("medical_record.forms.medical_case.status.review", fallback: "复查中")),
            ("pending_diagnosis", L10n.text("medical_record.forms.medical_case.status.pending_diagnosis", fallback: "待诊断")),
            ("chronic_management", L10n.text("medical_record.forms.medical_case.status.chronic_management", fallback: "慢性管理")),
        ]
    }

    static func normalizedStatusValue(_ value: String?) -> String? {
        guard let value = value?.nilIfBlank else { return nil }
        switch value {
        case "治疗中":
            return "in_treatment"
        case "已治愈", "已痊愈":
            return "cured"
        case "复查中", "复诊":
            return "review"
        case "待诊断":
            return "pending_diagnosis"
        case "慢性管理", "慢病管理":
            return "chronic_management"
        default:
            return value
        }
    }
}

private struct OptionalMenuPickerRow: View {
    let title: String
    @Binding var selection: String?
    let options: [(value: String, label: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: $selection) {
                Text(L10n.text("medical_record.forms.medical_case.option.none", fallback: "未选择")).tag(String?.none)
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(Optional(option.value))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        }
    }
}

// MARK: - GridTwo

struct GridTwo<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            content()
        }
    }
}

// MARK: - Selected member row (aligned with Health `SelectedPatientRow`)

private struct MedicalCaseSelectedMemberRow: View {
    var displayName: String
    var relationshipBadge: String?
    var subtitle: String?
    var onClear: () -> Void

    var body: some View {
        HStack {
            ZStack {
                Circle().fill(Color.blue.opacity(0.12))
                Text(String(displayName.prefix(2)))
                    .foregroundStyle(.blue)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName).font(.body.weight(.semibold))
                    if let relationshipBadge {
                        Badge(text: relationshipBadge)
                    }
                }
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.25)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.35)))
    }

    private struct Badge: View {
        var text: String
        var tintBG: Color = .gray.opacity(0.12)
        var tintFG: Color = .primary
        var body: some View {
            Text(text)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(tintBG))
                .foregroundStyle(tintFG)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(tintFG.opacity(0.25)))
        }
    }
}

struct MedicalCaseActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum MedicalCasePDFExporter {
    static func makePDF(
        item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        timelineEvents: [MedicalCaseTimelineEvent] = [],
        attachments: [SparkMedicalSyncAPI.RemoteManagedFile] = [],
        fileTransferService: FileTransferService? = nil
    ) async throws -> URL {
        let resolvedAttachments = await resolveAttachments(attachments, fileTransferService: fileTransferService)
        var resolvedTimelineAttachments: [String: [ResolvedAttachment]] = [:]
        for event in timelineEvents {
            resolvedTimelineAttachments[event.id] = await resolveAttachments(
                timelineAttachments(for: event),
                fileTransferService: fileTransferService
            )
        }

        return try makePDF(
            item: item,
            completeData: completeData,
            timelineEvents: timelineEvents,
            attachments: resolvedAttachments,
            timelineAttachments: resolvedTimelineAttachments
        )
    }

    static func makePDF(
        item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        timelineEvents: [MedicalCaseTimelineEvent] = [],
        attachments: [ResolvedAttachment] = [],
        timelineAttachments: [String: [ResolvedAttachment]] = [:]
    ) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(for: item))
            .appendingPathExtension("pdf")

        try renderer.writePDF(to: url) { context in
            let writer = PDFPageWriter(context: context, pageRect: pageRect)

            writer.drawTitle(L10n.text("medical_record.forms.medical_case.pdf.title", fallback: "就医文档"))
            writer.drawLine(L10n.text("medical_record.forms.medical_case.pdf.member", fallback: "成员"), value: memberName(for: item.member, completeData: completeData))
            writer.drawLine(L10n.text("medical_record.forms.medical_case.field.visit_date", fallback: "就诊日期"), value: visitDateText(for: item))
            writer.drawLine(L10n.text("medical_record.forms.medical_case.field.institution", fallback: "就诊机构"), value: item.hospitalName?.nonEmpty ?? emptyValue)
            writer.addSpacing(12)

            writer.drawSection(L10n.text("medical_record.forms.medical_case.field.chief_complaint", fallback: "主诉"), value: item.title?.nonEmpty ?? emptyValue)
            writer.drawSection(L10n.text("medical_record.forms.medical_case.field.diagnosis", fallback: "初步诊断"), value: item.diagnosisSummary?.nonEmpty ?? emptyValue)
            writer.drawSection(L10n.text("medical_record.forms.medical_case.field.present_illness", fallback: "现病史"), value: item.extra?["present_illness"]?.nonEmpty ?? emptyValue)
            writer.drawSection(L10n.text("medical_record.forms.medical_case.field.past_history", fallback: "既往史"), value: item.extra?["past_history"]?.nonEmpty ?? emptyValue)
            writer.drawSection(L10n.text("medical_record.forms.field.notes"), value: item.extra?["notes"]?.nonEmpty ?? emptyValue)

            if attachments.isEmpty == false {
                writer.drawSectionTitle(L10n.text("medical_record.forms.medical_case.pdf.attachments", fallback: "病历附件"))
                drawAttachments(attachments, writer: writer)
            }

            if timelineEvents.isEmpty == false {
                writer.drawSectionTitle(L10n.text("medical_record.forms.medical_case.pdf.timeline", fallback: "时间线"))
                for event in timelineEvents {
                    drawTimelineEvent(event, attachments: timelineAttachments[event.id] ?? [], writer: writer)
                }
            }
        }

        return url
    }

    private static func safeFileName(for item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> String {
        let base = item.title?.nonEmpty ?? "medical-case-\(item.id)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = base.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
        return String(scalars.joined().prefix(48))
    }

    private static func memberName(for memberID: Int, completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?) -> String {
        if completeData?.member.id == memberID {
            return completeData?.member.name ?? "\(memberID)"
        }
        return "\(memberID)"
    }

    private static func visitDateText(for item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> String {
        if let raw = item.extra?["visit_date"], raw.isEmpty == false {
            return raw
        }
        let date = item.updatedAt ?? item.createdAt ?? Date()
        return MedicalDateCoding.encodeDateOnly(date)
    }

    private static var emptyValue: String {
        L10n.text("medical_record.forms.medical_case.pdf.empty", fallback: "未填写")
    }

    private static func drawTimelineEvent(_ event: MedicalCaseTimelineEvent, attachments: [ResolvedAttachment], writer: PDFPageWriter) {
        let header = "\(dateFormatter.string(from: event.date)) · \(timelineKindText(event.kind))"
        writer.drawText(header, font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabel, spacingAfter: 4)
        writer.drawText(event.title, font: .boldSystemFont(ofSize: 14), color: .label, spacingAfter: 4)

        if let badge = event.statusBadgeText?.nonEmpty {
            writer.drawText(badge, font: .systemFont(ofSize: 11, weight: .medium), color: .systemOrange, spacingAfter: 4)
        }
        if event.detail.isEmpty == false {
            writer.drawText(event.detail, font: .systemFont(ofSize: 12), color: .label, spacingAfter: 6)
        }

        if let prescription = event.prescription {
            drawOptionalLine(L10n.text("medical_record.forms.field.institution"), value: prescription.institutionName, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.prescriber"), value: prescription.prescriberName, writer: writer)
            drawOptionalLine(L10n.text("common.prescription"), value: prescription.prescriptionNo, writer: writer)
            if event.nestedMedicationPlans.isEmpty == false {
                writer.drawText("服药计划 \(event.nestedMedicationPlans.count) 项", font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabel, spacingAfter: 4)
                for plan in event.nestedMedicationPlans {
                    writer.drawBullet(medicationPlanSummary(plan, box: plan.medicineBox.flatMap { event.medicineBoxesByID[$0] }))
                }
            }
        }
        if let plan = event.medicationPlan {
            writer.drawBullet(medicationPlanSummary(plan, box: plan.medicineBox.flatMap { event.medicineBoxesByID[$0] }))
        }

        if let examination = event.examination {
            drawOptionalLine(L10n.text("medical_record.forms.field.hospital"), value: examination.organizationName, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.department"), value: examination.departmentName, writer: writer)
        }
        if let visit = event.visit {
            drawOptionalLine(L10n.text("medical_record.forms.field.visit_type"), value: visit.visitType, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.doctor_name"), value: visit.doctorName, writer: writer)
        }
        if let surgery = event.surgery {
            drawOptionalLine(L10n.text("medical_record.forms.field.procedure_code"), value: surgery.procedureCode, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.surgeon"), value: surgery.surgeon, writer: writer)
        }
        if let followUp = event.followUp {
            drawOptionalLine(L10n.text("medical_record.forms.field.method"), value: followUp.method, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.outcome"), value: followUp.outcome, writer: writer)
        }
        if let symptom = event.symptom {
            drawOptionalLine(L10n.text("medical_record.forms.field.severity"), value: symptom.severity, writer: writer)
            drawOptionalLine(L10n.text("medical_record.forms.field.body_part"), value: symptom.bodyPart, writer: writer)
        }

        if attachments.isEmpty == false {
            writer.drawText(L10n.text("common.attachments"), font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabel, spacingAfter: 4)
            drawAttachments(attachments, writer: writer)
        }

        writer.addSpacing(12)
        writer.drawSeparator()
    }

    private static func drawAttachments(_ attachments: [ResolvedAttachment], writer: PDFPageWriter) {
        for attachment in attachments {
            writer.drawBullet(attachmentSummary(attachment.file))
            if let localURL = attachment.localURL {
                writer.drawAttachmentFile(localURL, displayName: attachment.file.displayName, mimeType: attachment.file.mimeType)
            }
        }
        writer.addSpacing(6)
    }

    private static func timelineAttachments(for event: MedicalCaseTimelineEvent) -> [SparkMedicalSyncAPI.RemoteManagedFile] {
        if let attachments = event.examination?.attachments, attachments.isEmpty == false {
            return attachments
        }
        return []
    }

    private static func resolveAttachments(
        _ attachments: [SparkMedicalSyncAPI.RemoteManagedFile],
        fileTransferService: FileTransferService?
    ) async -> [ResolvedAttachment] {
        var resolved: [ResolvedAttachment] = []
        for attachment in attachments {
            var localURL: URL?
            if let fileTransferService, let managedFile = attachment.managedFileRecord {
                if let cached = await fileTransferService.cachedURL(file: managedFile) {
                    localURL = cached
                } else {
                    localURL = try? await fileTransferService.download(file: managedFile)
                }
            }
            resolved.append(ResolvedAttachment(file: attachment, localURL: localURL))
        }
        return resolved
    }

    private static func drawOptionalLine(_ label: String, value: String?, writer: PDFPageWriter) {
        guard let value = value?.nonEmpty else { return }
        writer.drawText("\(label): \(value)", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacingAfter: 3)
    }

    private static func attachmentSummary(_ attachment: SparkMedicalSyncAPI.RemoteManagedFile) -> String {
        [
            attachment.displayName,
            attachment.fileSizeText,
            attachment.mimeType?.nonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func medicationPlanSummary(
        _ plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        box: SparkMedicalSyncAPI.RemoteMedicineBox?
    ) -> String {
        [
            plan.drugName.nilIfBlank,
            plan.dosePerTime.nilIfBlank,
            plan.frequencyText.nilIfBlank,
            plan.reminderTimes.map(\.time).joined(separator: ", ").nilIfBlank,
            box?.totalQuantity.map { "药箱存量 \($0.formatted(.number.precision(.fractionLength(0...2))))" },
            plan.instructions.nilIfBlank
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func timelineKindText(_ kind: MedicalCaseTimelineKind) -> String {
        switch kind {
        case .symptom:
            return L10n.text("home.medical.case_detail.add.menu.symptom")
        case .prescription:
            return L10n.text("common.prescription", fallback: "处方")
        case .medication:
            return L10n.text("common.medication", fallback: "用药")
        case .examination(let category):
            return L10n.text(category.titleKey)
        case .visit:
            return L10n.text("home.medical.case_detail.add.menu.visit")
        case .surgery:
            return L10n.text("home.medical.case_detail.add.menu.surgery")
        case .followUp:
            return L10n.text("home.medical.case_detail.add.menu.follow_up")
        case .meta:
            return L10n.text("home.medical.case_detail.meta.title")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    struct ResolvedAttachment {
        let file: SparkMedicalSyncAPI.RemoteManagedFile
        let localURL: URL?
    }

    private final class PDFPageWriter {
        private let context: UIGraphicsPDFRendererContext
        private let pageRect: CGRect
        private let inset: CGFloat = 42
        private var y: CGFloat = 42

        private var width: CGFloat { pageRect.width - inset * 2 }
        private var bottomLimit: CGFloat { pageRect.height - inset }

        init(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
            self.context = context
            self.pageRect = pageRect
            context.beginPage()
        }

        func drawTitle(_ text: String) {
            drawText(text, font: .boldSystemFont(ofSize: 24), color: .label, spacingAfter: 18)
        }

        func drawSectionTitle(_ text: String) {
            addSpacing(8)
            drawText(text, font: .boldSystemFont(ofSize: 17), color: .label, spacingAfter: 10)
        }

        func drawSection(_ title: String, value: String) {
            addSpacing(8)
            drawText(title, font: .boldSystemFont(ofSize: 15), color: .label, spacingAfter: 6)
            drawText(value, font: .systemFont(ofSize: 13), color: .label, spacingAfter: 10)
        }

        func drawLine(_ label: String, value: String) {
            drawText("\(label): \(value)", font: .systemFont(ofSize: 12), color: .label, spacingAfter: 8)
        }

        func drawBullet(_ text: String) {
            drawText("• \(text)", font: .systemFont(ofSize: 11), color: .label, spacingAfter: 4)
        }

        func drawAttachmentFile(_ url: URL, displayName: String, mimeType: String?) {
            if isImage(url: url, mimeType: mimeType), let image = UIImage(contentsOfFile: url.path) {
                drawImage(image, caption: displayName)
                return
            }

            if isPDF(url: url, mimeType: mimeType), let document = PDFDocument(url: url) {
                drawPDFDocument(document, displayName: displayName)
                return
            }

            drawText(
                L10n.text("medical_record.forms.medical_case.pdf.unsupported_attachment", fallback: "该附件类型暂不支持嵌入预览，已保留文件信息。"),
                font: .italicSystemFont(ofSize: 10),
                color: .secondaryLabel,
                spacingAfter: 6
            )
        }

        private func drawImage(_ image: UIImage, caption: String) {
            drawText(caption, font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabel, spacingAfter: 4)
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let maxHeight = pageRect.height - inset * 2
            let scale = min(width / imageSize.width, maxHeight / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            ensureSpace(drawSize.height + 10)
            let rect = CGRect(x: inset + (width - drawSize.width) / 2, y: y, width: drawSize.width, height: drawSize.height)
            image.draw(in: rect)
            y += drawSize.height + 10
        }

        private func drawPDFDocument(_ document: PDFDocument, displayName: String) {
            guard document.pageCount > 0 else { return }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                drawPDFPage(page, displayName: displayName, pageIndex: index + 1, pageCount: document.pageCount)
            }
        }

        private func drawPDFPage(_ page: PDFPage, displayName: String, pageIndex: Int, pageCount: Int) {
            let caption = pageCount > 1
                ? "\(displayName) (\(pageIndex)/\(pageCount))"
                : displayName
            drawText(caption, font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabel, spacingAfter: 4)

            let source = page.bounds(for: .mediaBox)
            guard source.width > 0, source.height > 0 else { return }
            let maxHeight = pageRect.height - inset * 2
            let scale = min(width / source.width, maxHeight / source.height)
            let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
            ensureSpace(drawSize.height + 10)

            let rect = CGRect(x: inset + (width - drawSize.width) / 2, y: y, width: drawSize.width, height: drawSize.height)
            UIColor.white.setFill()
            UIBezierPath(rect: rect).fill()

            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: rect.minX, y: rect.maxY)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -source.minX, y: -source.minY)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()

            y += drawSize.height + 10
        }

        func drawSeparator() {
            ensureSpace(12)
            UIColor.separator.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: inset, y: y))
            path.addLine(to: CGPoint(x: inset + width, y: y))
            path.lineWidth = 0.5
            path.stroke()
            y += 10
        }

        func addSpacing(_ spacing: CGFloat) {
            ensureSpace(spacing)
            y += spacing
        }

        func drawText(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let rect = NSString(string: text).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            let height = ceil(rect.height)
            ensureSpace(height + spacingAfter)
            NSString(string: text).draw(in: CGRect(x: inset, y: y, width: width, height: height), withAttributes: attributes)
            y += height + spacingAfter
        }

        private func ensureSpace(_ height: CGFloat) {
            guard y + height > bottomLimit else { return }
            context.beginPage()
            y = inset
        }

        private func isImage(url: URL, mimeType: String?) -> Bool {
            let ext = url.pathExtension.lowercased()
            let mime = mimeType?.lowercased() ?? ""
            return mime.contains("image") || ["png", "jpg", "jpeg", "heic", "webp"].contains(ext)
        }

        private func isPDF(url: URL, mimeType: String?) -> Bool {
            url.pathExtension.lowercased() == "pdf" || (mimeType?.lowercased().contains("pdf") ?? false)
        }
    }
}
