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
    /// 转换为检查报告创建请求
    func toExaminationReportCreateRequest(sourceFileIds: [Int] = []) -> ExaminationReportCreateRequest {
        ExaminationReportCreateRequest(
            category: category ?? "unknown",
            itemName: title,
            findings: content,
            impression: nil,
            performedAt: date,
            organizationName: hospital,
            doctorName: doctor,
            details: details.map { $0.toExaminationReportDetailRequest() },
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
