import Foundation

// MARK: - Symptom Recognition Draft Mappers

extension SymptomRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest() -> SymptomCreateRequest {
        SymptomCreateRequest(
            name: name,
            code: code,
            severity: severity,
            startedAt: startedAt,
            durationValue: durationValue.parsedAsAgeAtVisitInteger(),
            durationUnit: durationUnit,
            bodyPart: bodyPart,
            notes: notes
        )
    }
}

// MARK: - Visit Recognition Draft Mappers

extension VisitRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest() -> VisitCreateRequest {
        VisitCreateRequest(
            visitType: visitType,
            visitedAt: visitedAt,
            department: department,
            doctorName: doctorName,
            visitNo: visitNo,
            notes: notes
        )
    }
}

// MARK: - Surgery Recognition Draft Mappers

extension SurgeryRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest() -> SurgeryCreateRequest {
        SurgeryCreateRequest(
            procedureName: procedureName,
            procedureCode: procedureCode,
            site: site,
            performedAt: performedAt,
            surgeon: surgeon,
            anesthesiaType: anesthesiaType,
            incisionLevel: incisionLevel,
            asaClass: asaClass,
            notes: notes
        )
    }
}

// MARK: - FollowUp Recognition Draft Mappers

extension FollowUpRecognitionDraft {
    /// 转换为创建请求
    func toCreateRequest() -> FollowUpCreateRequest {
        FollowUpCreateRequest(
            plannedAt: plannedAt,
            completedAt: completedAt,
            status: status,
            method: method,
            outcome: outcome,
            nextAction: nextAction
        )
    }
}

// MARK: - Case Recognition Draft Mappers

extension CaseRecognitionDraft {
    /// 转换为病历创建请求
    func toMedicalCaseCreateRequest() -> MedicalCaseCreateRequest {
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
            extra: extraDict.isEmpty ? nil : extraDict
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
    func toExaminationReportCreateRequest() -> ExaminationReportCreateRequest {
        ExaminationReportCreateRequest(
            category: category ?? "unknown",
            itemName: title,
            findings: content,
            impression: nil,
            performedAt: date,
            organizationName: hospital,
            doctorName: doctor,
            details: details.map { $0.toExaminationReportDetailRequest() }
        )
    }
}

// MARK: - Medication Recognition Draft Mappers

extension MedicationRecognitionDraft {
    /// 转换为处方用药创建请求
    /// 数值字段从 OCR 字符串转换为实际数值类型
    func toPrescriptionMedicationRequest() -> PrescriptionMedicationRequest {
        PrescriptionMedicationRequest(
            genericName: genericName,
            brandName: brandName,
            drugName: drugName,
            dosageForm: dosageForm,
            strength: strength,
            route: route,
            dosePerTime: dosePerTime,
            doseValue: doseValue.parsedAsDoseValue(),
            doseUnit: doseUnit,
            frequencyCode: frequencyCode,
            period: period,
            timesPerPeriod: timesPerPeriod.parsedAsTimesPerPeriod(),
            frequencyText: frequencyText,
            durationDays: durationDays.parsedAsDurationDays(),
            instructions: instructions,
            sortOrder: sortOrder.parsedAsSortOrderInt(),
            extra: extra
        )
    }
}

// MARK: - Prescription Recognition Draft Mappers

extension PrescriptionRecognitionDraft {
    /// 转换为处方批次创建请求
    func toPrescriptionBatchCreateRequest() -> PrescriptionBatchCreateRequest {
        PrescriptionBatchCreateRequest(
            prescriberName: prescriberName,
            institutionName: institutionName,
            prescribedAt: prescribedAt,
            diagnosis: diagnosis,
            batchNo: batchNo,
            status: status,
            medications: medications?.map { $0.toPrescriptionMedicationRequest() }
        )
    }
}

// MARK: - Health Exam Recognition Draft Mappers

extension HealthExamRecognitionDraft {
    /// 转换为检查报告创建请求列表（将体检报告拆分为多个检查报告）
    func toExaminationReportCreateRequests() -> [ExaminationReportCreateRequest] {
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
                details: items.map { $0.toExaminationReportDetailRequest() }
            )
        }
    }
}
