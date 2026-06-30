import Foundation

// MARK: - Symptom Recognition Draft Mappers

extension SymptomRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest(sourceFileIds: [Int] = []) -> SymptomCreateRequest {
        SymptomCreateRequest(
            name: name,
            code: code,
            severity: severity,
            startedAt: startedAt,
            durationValue: durationValue.parsedAsAgeAtVisitInteger(),
            durationUnit: durationUnit,
            bodyPart: bodyPart,
            notes: notes,
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - Visit Recognition Draft Mappers

extension VisitRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest(sourceFileIds: [Int] = []) -> VisitCreateRequest {
        VisitCreateRequest(
            visitType: visitType,
            visitedAt: visitedAt,
            department: department,
            doctorName: doctorName,
            visitNo: visitNo,
            notes: notes,
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - Surgery Recognition Draft Mappers

extension SurgeryRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest(sourceFileIds: [Int] = []) -> SurgeryCreateRequest {
        SurgeryCreateRequest(
            procedureName: procedureName,
            procedureCode: procedureCode,
            site: site,
            performedAt: performedAt,
            surgeon: surgeon,
            anesthesiaType: anesthesiaType,
            incisionLevel: incisionLevel,
            asaClass: asaClass,
            notes: notes,
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - FollowUp Recognition Draft Mappers

extension FollowUpRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest(sourceFileIds: [Int] = []) -> FollowUpCreateRequest {
        FollowUpCreateRequest(
            plannedAt: plannedAt,
            completedAt: completedAt,
            status: status,
            method: method,
            outcome: outcome,
            nextAction: nextAction,
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - Case Recognition Draft Mappers

extension CaseRecognitionDraft {
    /// 转换为病历创建请求
    func toMedicalCaseCreateRequest(sourceFileIds: [Int] = []) -> MedicalCaseCreateRequest {
        // 合并 summary 和 diagnosis 作为诊断摘要
        let diagnosisParts: [String] = [summary, diagnosis].compactMap { $0 }.filter { !$0.isEmpty }
        let diagnosisSummary = diagnosisParts.isEmpty ? nil : diagnosisParts.joined(separator: "\n")

        // 将 occurredAt 放入 extra 中，因为后端 MedicalCase 模型没有 occurred_at 字段
        var extraDict: [String: String] = [:]
        if let occurredAt = occurredAt {
            extraDict["occurred_at"] = occurredAt
        }

        return MedicalCaseCreateRequest(
            title: title,
            hospitalName: hospitalName,
            diagnosisSummary: diagnosisSummary,
            ageAtVisit: ageAtVisit.parsedAsAgeAtVisitInteger(),
            extra: extraDict.isEmpty ? nil : extraDict,
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - Medical Report Item Draft Mappers

extension ItemDraft {
    init(medicalReportItem item: MedicalReportItem) {
        self.init(
            category: item.category,
            subCategory: item.subCategory,
            itemName: item.itemName,
            resultValue: item.resultValue,
            unit: item.unit,
            referenceRange: item.referenceRange,
            flag: item.flag,
            modality: item.modality,
            bodyPart: item.bodyPart,
            resultAt: item.resultAt,
            diagnosis: item.diagnosis
        )
    }

    /// 转换为 API 落库用的 `MedicalReportItem`（保留排序序号等元数据）
    func toMedicalReportItem(fallbackCategory: String? = nil, sortOrder: Int) -> MedicalReportItem {
        MedicalReportItem(
            category: (category ?? "").nilIfBlank ?? (fallbackCategory ?? "").nilIfBlank ?? fallbackCategory ?? "",
            subCategory: subCategory?.nilIfBlank,
            itemName: itemName?.nilIfBlank,
            itemCode: nil,
            resultValue: resultValue?.nilIfBlank,
            unit: unit?.nilIfBlank,
            referenceRange: referenceRange?.nilIfBlank,
            flag: flag?.nilIfBlank,
            resultAt: resultAt?.nilIfBlank,
            modality: modality?.nilIfBlank,
            bodyPart: bodyPart?.nilIfBlank,
            diagnosis: diagnosis?.nilIfBlank,
            extra: nil,
            sortOrder: "\(sortOrder)"
        )
    }

    /// 转换为检查报告明细创建请求
    func toExaminationReportDetailRequest(fallbackCategory: String? = nil, sortOrder: Int) -> ExaminationReportDetailRequest {
        toMedicalReportItem(fallbackCategory: fallbackCategory, sortOrder: sortOrder)
            .toExaminationReportDetailRequest()
    }
}

// MARK: - Medical Report Item Mappers

extension MedicalReportItem {
    /// 转换为检查报告明细创建请求
    func toExaminationReportDetailRequest() -> ExaminationReportDetailRequest {
        ExaminationReportDetailRequest(
            category: category,
            subCategory: subCategory,
            itemName: itemName,
            itemCode: itemCode,
            resultValue: resultValue ?? "",
            unit: unit,
            referenceRange: referenceRange,
            flag: flag,
            resultAt: resultAt,
            modality: modality,
            bodyPart: bodyPart,
            diagnosis: diagnosis,
            sortOrder: sortOrder.parsedAsSortOrderInt(),
            extra: extra
        )
    }
}

// MARK: - Medical Report Recognition Draft Mappers

extension MedicalReportRecognitionDraft {
    private var isImagingOrPathologyCategory: Bool {
        switch (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "imaging", "pathology":
            return true
        default:
            return false
        }
    }

    /// 报告头「所见」：优先 `content`。
    var resolvedFindingsText: String? {
        content?.nilIfBlank
    }

    /// 报告头「印象/结论」：影像/病理拼接全部 `details.diagnosis`；其他类型与 `content` 一致。
    var resolvedImpressionText: String? {
        if isImagingOrPathologyCategory {
            let joined = details.compactMap(\.diagnosis?.nilIfBlank).joined(separator: "\n")
            if joined.isEmpty == false {
                return joined
            }
        }
        return content?.nilIfBlank
    }

    /// 转换为检查报告创建请求
    func toExaminationReportCreateRequest(sourceFileIds: [Int] = []) -> ExaminationReportCreateRequest {
        ExaminationReportCreateRequest(
            category: category ?? "unknown",
            itemName: title,
            findings: resolvedFindingsText,
            impression: resolvedImpressionText,
            performedAt: date,
            organizationName: hospital,
            doctorName: doctor,
            details: details.enumerated().map { index, row in
                row.toExaminationReportDetailRequest(fallbackCategory: category, sortOrder: index)
            },
            sourceFileIds: sourceFileIds
        )
    }
}

// MARK: - Health Exam Recognition Draft Mappers

extension HealthExamRecognitionDraft {
    /// 转换为检查报告创建请求列表（将体检报告拆分为多个检查报告）
    func toExaminationReportCreateRequests(sourceFileIds: [Int] = []) -> [ExaminationReportCreateRequest] {
        // 按类别分组创建检查报告
        let groupedByCategory = Dictionary(grouping: items) { $0.category }

        return groupedByCategory.map { category, items in
            ExaminationReportCreateRequest(
                category: category,
                itemName: "\(category)检查",
                findings: nil,
                impression: category == groupedByCategory.keys.first ? summary : nil,
                performedAt: examDate,
                organizationName: institutionName,
                doctorName: nil,
                details: items.map { $0.toExaminationReportDetailRequest() },
                sourceFileIds: sourceFileIds
            )
        }
    }
}
