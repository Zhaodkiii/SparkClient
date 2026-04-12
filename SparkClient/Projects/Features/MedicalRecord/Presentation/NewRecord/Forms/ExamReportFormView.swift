import SwiftUI

struct ExamReportFormView: View {
    enum Mode {
        case create
        case serverEdit(existing: MedicalReportRecognitionDraft)
        case localEdit(existing: MedicalReportRecognitionDraft, onSubmit: (MedicalReportRecognitionDraft) -> Void)
    }

    enum PageType: String, CaseIterable {
        case laboratory
        case imaging
        case pathology

        var title: String { rawValue }
        var itemLabel: String {
            switch self {
            case .laboratory: return "检验项目"
            case .imaging: return "影像项目"
            case .pathology: return "病理项目"
            }
        }
    }

    struct ItemDraft: Identifiable {
        var id = UUID()
        var category: String = ""
        var subCategory: String = ""
        var itemName: String = ""
        var resultValue: String = ""
        var unit: String = ""
        var referenceRange: String = ""
        var flag: String = ""
    }

    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let onCreateSubmit: ((MedicalReportRecognitionDraft) async throws -> Void)?
    let onServerSubmit: ((MedicalReportRecognitionDraft) async throws -> Void)?

    @State private var pageType: PageType
    @State private var category: String
    @State private var title: String
    @State private var hospital: String
    @State private var doctor: String
    @State private var content: String
    @State private var date: String
    @State private var items: [ItemDraft]
    @State private var editingItem: ItemDraft?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        mode: Mode,
        onCreateSubmit: ((MedicalReportRecognitionDraft) async throws -> Void)? = nil,
        onServerSubmit: ((MedicalReportRecognitionDraft) async throws -> Void)? = nil
    ) {
        self.mode = mode
        self.onCreateSubmit = onCreateSubmit
        self.onServerSubmit = onServerSubmit

        let seed: MedicalReportRecognitionDraft
        switch mode {
        case .create:
            seed = .init(category: "laboratory", title: "", hospital: "", doctor: "", content: "", date: "", details: [])
        case .serverEdit(let existing), .localEdit(let existing, _):
            seed = existing
        }

        let pageType = ExamReportFormView.detectPageType(seed.category)
        _pageType = State(initialValue: pageType)
        _category = State(initialValue: seed.category ?? pageType.rawValue)
        _title = State(initialValue: seed.title)
        _hospital = State(initialValue: seed.hospital ?? "")
        _doctor = State(initialValue: seed.doctor ?? "")
        _content = State(initialValue: seed.content)
        _date = State(initialValue: seed.date ?? "")
        _items = State(initialValue: seed.details.map {
            ItemDraft(
                category: $0.category,
                subCategory: $0.subCategory ?? "",
                itemName: $0.itemName ?? "",
                resultValue: $0.resultValue ?? "",
                unit: $0.unit ?? "",
                referenceRange: $0.referenceRange ?? "",
                flag: $0.flag ?? ""
            )
        })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SparkFormCard(title: navTitle) {
                    Picker("子页面", selection: $pageType) {
                        ForEach(PageType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: pageType) { newValue in
                        category = newValue.rawValue
                    }

                    SparkFormTextRow(title: "分类", text: $category)
                    SparkFormTextRow(title: "报告标题", text: $title)
                    SparkFormTextRow(title: "医院", text: $hospital)
                    SparkFormTextRow(title: "医生", text: $doctor)
                    SparkFormTextRow(title: "日期", text: $date, placeholder: "yyyy-MM-dd")
                    SparkFormTextAreaRow(title: "报告内容", text: $content)
                }

                SparkFormCard(title: "\(pageType.itemLabel)子项") {
                    Button("新增子项") {
                        editingItem = .init()
                    }
                    .buttonStyle(.bordered)

                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.itemName.isEmpty ? "未命名子项" : item.itemName)
                                .font(.subheadline.weight(.semibold))
                            Text("结果：\(item.resultValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                        .onTapGesture { editingItem = item }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(saveTitle) { saveNow() }
                    .disabled(isSaving)
            }
        }
        .sheet(item: $editingItem) { item in
            AddLabItemSheet(draft: .init(
                category: item.category,
                subCategory: item.subCategory,
                itemName: item.itemName,
                resultValue: item.resultValue,
                unit: item.unit,
                referenceRange: item.referenceRange,
                flag: item.flag
            )) { newItem in
                let mapped = ItemDraft(
                    category: newItem.category,
                    subCategory: newItem.subCategory,
                    itemName: newItem.itemName,
                    resultValue: newItem.resultValue,
                    unit: newItem.unit,
                    referenceRange: newItem.referenceRange,
                    flag: newItem.flag
                )
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = mapped
                } else {
                    items.append(mapped)
                }
            }
        }
        .alert("提交失败", isPresented: Binding(get: { errorMessage != nil }, set: { if $0 == false { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var navTitle: String {
        switch mode {
        case .create: return "新增医疗检查报告"
        case .serverEdit: return "编辑医疗检查报告"
        case .localEdit: return "编辑医疗检查报告（本地）"
        }
    }

    private var saveTitle: String {
        switch mode {
        case .create: return "保存"
        case .serverEdit: return "更新"
        case .localEdit: return "完成"
        }
    }

    private func saveNow() {
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
                resultAt: nil,
                modality: nil,
                bodyPart: nil,
                diagnosis: nil,
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
            dismiss()
        case .create:
            guard let onCreateSubmit else { dismiss(); return }
            isSaving = true
            Task {
                do {
                    try await onCreateSubmit(draft)
                    await MainActor.run { dismiss() }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
                await MainActor.run { isSaving = false }
            }
        case .serverEdit:
            guard let onServerSubmit else { dismiss(); return }
            isSaving = true
            Task {
                do {
                    try await onServerSubmit(draft)
                    await MainActor.run { dismiss() }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
                await MainActor.run { isSaving = false }
            }
        }
    }

    private static func detectPageType(_ category: String?) -> PageType {
        let lower = (category ?? "").lowercased()
        if lower.contains("path") || lower.contains("病理") { return .pathology }
        if lower.contains("image") || lower.contains("影像") || lower.contains("ct") || lower.contains("mr") { return .imaging }
        return .laboratory
    }
}
