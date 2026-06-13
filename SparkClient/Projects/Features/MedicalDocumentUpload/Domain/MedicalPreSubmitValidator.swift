import Foundation

protocol MedicalPreSubmitValidating: Sendable {
    func validate(output: MedicalDocumentTypedExtractionOutput) -> [MedicalPreSubmitValidationIssue]
}

struct MedicalPreSubmitValidator: MedicalPreSubmitValidating, Sendable {
    func validate(output: MedicalDocumentTypedExtractionOutput) -> [MedicalPreSubmitValidationIssue] {
        switch output.typedResult {
        case .caseDocument(let draft):
            return validateCaseDocument(draft)
        case .healthExamReport(let draft):
            return validateHealthExamReport(draft)
        case .medicalReport(let drafts):
            return validateMedicalReports(drafts)
        case .prescription(let drafts):
            var issues: [MedicalPreSubmitValidationIssue] = []
            if drafts.isEmpty {
                issues.append(issue(
                    resourceType: .prescription,
                    fieldPath: "prescriptions",
                    fieldKey: "prescriptions",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.prescription"),
                    message: L10n.text("medical.upload.result.prescription.empty_batches"),
                    sectionTitle: L10n.text("medical.upload.presubmit.section.prescription")
                ))
            }
            for (prescriptionIndex, prescription) in drafts.enumerated() {
                issues.append(contentsOf: validatePrescription(
                    prescription,
                    prescriptionIndex: prescriptionIndex
                ))
            }
            return issues
        case .medicationPlan(let drafts):
            return validateMedicationPlans(drafts, prescriptionIndex: nil)
        case .medicineBoxes(let drafts):
            return validateMedicineBoxes(drafts)
        }
    }

    // MARK: - Case

    private func validateCaseDocument(_ draft: CaseRecognitionDraft) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let caseSection = L10n.text("medical.upload.presubmit.section.case_history")

        if MedicalPreSubmitValidationRules.isBlank(draft.title) {
            issues.append(issue(
                resourceType: .caseDocument,
                fieldPath: "medical_case.title",
                fieldKey: "medical_case.title",
                fieldLabel: L10n.text("medical.upload.presubmit.field.case_title"),
                message: MedicalPreSubmitValidationRules.requiredFieldMessage(
                    fieldLabel: L10n.text("medical.upload.presubmit.field.case_title")
                ),
                sectionTitle: caseSection
            ))
        }

        if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(draft.occurredAt) == false {
            issues.append(dateIssue(
                fieldPath: "medical_case.occurred_at",
                fieldKey: "medical_case.occurred_at",
                fieldLabel: L10n.text("medical.upload.presubmit.field.occurred_at"),
                sectionTitle: caseSection
            ))
        }

        if let age = draft.ageAtVisit?.trimmingCharacters(in: .whitespacesAndNewlines), age.isEmpty == false {
            if Optional(age).parsedAsAgeAtVisitInteger() == nil {
                issues.append(issue(
                    resourceType: .caseDocument,
                    fieldPath: "medical_case.age_at_visit",
                    fieldKey: "medical_case.age_at_visit",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.age_at_visit"),
                    message: MedicalPreSubmitValidationRules.validNumberMessage(),
                    sectionTitle: caseSection
                ))
            }
        }

        if let symptom = draft.symptom {
            let symptomSection = L10n.text("medical.upload.presubmit.section.symptom")
            if MedicalPreSubmitValidationRules.isBlank(symptom.name) {
                issues.append(issue(
                    resourceType: .symptom,
                    fieldPath: "symptom.name",
                    fieldKey: "symptom.name",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.symptom_name"),
                    message: MedicalPreSubmitValidationRules.requiredFieldMessage(
                        fieldLabel: L10n.text("medical.upload.presubmit.field.symptom_name")
                    ),
                    sectionTitle: symptomSection
                ))
            }
            if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(symptom.startedAt) == false {
                issues.append(dateIssue(
                    fieldPath: "symptom.started_at",
                    fieldKey: "symptom.started_at",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.started_at"),
                    sectionTitle: symptomSection
                ))
            }
        }

        if let visit = draft.visit {
            let visitSection = L10n.text("medical.upload.presubmit.section.visit")
            if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(visit.visitedAt) == false {
                issues.append(dateIssue(
                    fieldPath: "visit.visited_at",
                    fieldKey: "visit.visited_at",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.visited_at"),
                    sectionTitle: visitSection
                ))
            }
        }

        for (index, report) in (draft.examinationReports ?? []).enumerated() {
            issues.append(contentsOf: validateExaminationReport(
                report,
                index: index,
                sectionTitle: L10n.text("medical.upload.presubmit.section.examination_report")
            ))
        }

        for (prescriptionIndex, prescription) in (draft.prescriptions ?? []).enumerated() {
            issues.append(contentsOf: validatePrescription(
                prescription,
                prescriptionIndex: prescriptionIndex
            ))
        }

        return issues
    }

    // MARK: - Health exam

    private func validateHealthExamReport(_ draft: HealthExamRecognitionDraft) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let section = L10n.text("medical.upload.presubmit.section.health_exam")

        if MedicalPreSubmitValidationRules.isBlank(draft.institutionName) {
            issues.append(issue(
                resourceType: .healthExamReport,
                fieldPath: "health_exam.institution_name",
                fieldKey: "health_exam.institution_name",
                fieldLabel: L10n.text("medical.upload.presubmit.field.report_title"),
                message: MedicalPreSubmitValidationRules.requiredFieldMessage(
                    fieldLabel: L10n.text("medical.upload.presubmit.field.report_title")
                ),
                sectionTitle: section
            ))
        }

        if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(draft.examDate) == false {
            issues.append(dateIssue(
                fieldPath: "health_exam.exam_date",
                fieldKey: "health_exam.exam_date",
                fieldLabel: L10n.text("medical.upload.presubmit.field.exam_date"),
                sectionTitle: section
            ))
        }

        for (index, item) in draft.items.enumerated() {
            if MedicalPreSubmitValidationRules.isBlank(item.itemName) {
                issues.append(issue(
                    resourceType: .healthExamReport,
                    fieldPath: "health_exam.items[\(index)].item_name",
                    fieldKey: "health_exam.items[\(index)].item_name",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.item_name"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: index,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.item_name")
                    ),
                    sectionTitle: L10n.text("medical.upload.presubmit.section.health_exam_item"),
                    cardIndex: index
                ))
            }
            if MedicalPreSubmitValidationRules.isBlank(item.resultValue) {
                issues.append(issue(
                    resourceType: .healthExamReport,
                    fieldPath: "health_exam.items[\(index)].result_value",
                    fieldKey: "health_exam.items[\(index)].result_value",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.result_value"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: index,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.result_value")
                    ),
                    sectionTitle: L10n.text("medical.upload.presubmit.section.health_exam_item"),
                    cardIndex: index
                ))
            }
        }

        return issues
    }

    // MARK: - Medical reports

    private func validateMedicalReports(_ drafts: [MedicalReportRecognitionDraft]) -> [MedicalPreSubmitValidationIssue] {
        drafts.enumerated().flatMap { index, draft in
            validateExaminationReport(
                draft,
                index: index,
                sectionTitle: L10n.text("medical.upload.presubmit.section.examination_report")
            )
        }
    }

    private func validateExaminationReport(
        _ report: MedicalReportRecognitionDraft,
        index: Int,
        sectionTitle: String
    ) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []

        if MedicalPreSubmitValidationRules.isBlank(report.title) {
            issues.append(issue(
                resourceType: .examinationReport,
                fieldPath: "examination_reports[\(index)].item_name",
                fieldKey: "examination_reports[\(index)].item_name",
                fieldLabel: L10n.text("medical.upload.presubmit.field.report_name"),
                message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                    index: index,
                    fieldLabel: L10n.text("medical.upload.presubmit.field.report_name")
                ),
                sectionTitle: sectionTitle,
                cardIndex: index
            ))
        }

        if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(report.date) == false {
            issues.append(dateIssue(
                fieldPath: "examination_reports[\(index)].performed_at",
                fieldKey: "examination_reports[\(index)].performed_at",
                fieldLabel: L10n.text("medical.upload.presubmit.field.performed_at"),
                sectionTitle: sectionTitle,
                cardIndex: index
            ))
        }

        if MedicalPreSubmitValidationRules.isValidExaminationCategory(report.category) == false {
            issues.append(issue(
                resourceType: .examinationReport,
                fieldPath: "examination_reports[\(index)].category",
                fieldKey: "examination_reports[\(index)].category",
                fieldLabel: L10n.text("medical.upload.presubmit.field.report_category"),
                message: MedicalPreSubmitValidationRules.validEnumMessage(
                    fieldLabel: L10n.text("medical.upload.presubmit.field.report_category")
                ),
                sectionTitle: sectionTitle,
                cardIndex: index
            ))
        }

        let reportCategory = ExaminationReportCategory.from(report.category)
        for (detailIndex, detail) in report.details.enumerated() {
            if MedicalPreSubmitValidationRules.isBlank(detail.itemName) {
                issues.append(issue(
                    resourceType: .examinationReport,
                    fieldPath: "examination_reports[\(index)].details[\(detailIndex)].item_name",
                    fieldKey: "examination_reports[\(index)].details[\(detailIndex)].item_name",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.detail_item_name"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: detailIndex,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.detail_item_name")
                    ),
                    sectionTitle: sectionTitle,
                    cardIndex: index
                ))
            }
            // 实验室检查子项需填写结果数值；影像/病理结论在 diagnosis，不校验 resultValue。
            if reportCategory == .laboratory,
               MedicalPreSubmitValidationRules.isBlank(detail.resultValue) {
                issues.append(issue(
                    resourceType: .examinationReport,
                    fieldPath: "examination_reports[\(index)].details[\(detailIndex)].result_value",
                    fieldKey: "examination_reports[\(index)].details[\(detailIndex)].result_value",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.detail_result_value"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: detailIndex,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.detail_result_value")
                    ),
                    sectionTitle: sectionTitle,
                    cardIndex: index
                ))
            }
        }

        return issues
    }

    // MARK: - Prescription / medication

    private func validatePrescription(
        _ draft: PrescriptionRecognitionDraft,
        prescriptionIndex: Int
    ) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let section = L10n.text("medical.upload.presubmit.section.prescription")

        if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(draft.prescribedAt) == false {
            issues.append(dateIssue(
                fieldPath: "prescriptions[\(prescriptionIndex)].prescribed_at",
                fieldKey: "prescriptions[\(prescriptionIndex)].prescribed_at",
                fieldLabel: L10n.text("medical.upload.presubmit.field.prescribed_at"),
                sectionTitle: section,
                cardIndex: prescriptionIndex
            ))
        }

        issues.append(contentsOf: validateMedicationPlans(
            draft.medicationPlans ?? [],
            prescriptionIndex: prescriptionIndex
        ))

        return issues
    }

    private func validateMedicationPlans(
        _ plans: [MedicationPlanRecognitionDraft],
        prescriptionIndex: Int?
    ) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let section = L10n.text("medical.upload.presubmit.section.medication")

        for (planIndex, plan) in plans.enumerated() {
            let pathPrefix: String
            let cardIndex: Int
            if let prescriptionIndex {
                pathPrefix = "prescriptions[\(prescriptionIndex)].medication_plans[\(planIndex)]"
                cardIndex = planIndex
            } else {
                pathPrefix = "medication_plans[\(planIndex)]"
                cardIndex = planIndex
            }

            let drugName = plan.medicineName?.nilIfBlank
                ?? plan.medicineBox?.medicineName?.nilIfBlank
                ?? plan.brandName?.nilIfBlank

            if MedicalPreSubmitValidationRules.isBlank(drugName) {
                issues.append(issue(
                    resourceType: .medicationPlan,
                    fieldPath: "\(pathPrefix).drug_name",
                    fieldKey: "\(pathPrefix).drug_name",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.drug_name"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: planIndex,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.drug_name")
                    ),
                    sectionTitle: section,
                    cardIndex: cardIndex,
                    prescriptionIndex: prescriptionIndex
                ))
            }

            if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(plan.startDate) == false {
                issues.append(dateIssue(
                    fieldPath: "\(pathPrefix).start_date",
                    fieldKey: "\(pathPrefix).start_date",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.start_date"),
                    sectionTitle: section,
                    cardIndex: cardIndex,
                    prescriptionIndex: prescriptionIndex
                ))
            }

            let doseUnit = plan.doseUnit?.nilIfBlank ?? plan.medicineBox?.doseUnit?.nilIfBlank
            if doseUnit != nil, MedicalPreSubmitValidationRules.isBlank(plan.dosePerTime) {
                issues.append(issue(
                    resourceType: .medicationPlan,
                    fieldPath: "\(pathPrefix).dose_per_time",
                    fieldKey: "\(pathPrefix).dose_per_time",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.dose_per_time"),
                    message: MedicalPreSubmitValidationRules.requiredFieldMessage(
                        fieldLabel: L10n.text("medical.upload.presubmit.field.dose_per_time")
                    ),
                    sectionTitle: section,
                    cardIndex: cardIndex,
                    prescriptionIndex: prescriptionIndex
                ))
            }

            if MedicalPreSubmitValidationRules.isBlank(plan.frequencyType)
                || MedicalPreSubmitValidationRules.isValidFrequencyType(plan.frequencyType) == false {
                issues.append(issue(
                    resourceType: .medicationPlan,
                    fieldPath: "\(pathPrefix).frequency_type",
                    fieldKey: "\(pathPrefix).frequency_type",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.frequency_type"),
                    message: MedicalPreSubmitValidationRules.validEnumMessage(
                        fieldLabel: L10n.text("medical.upload.presubmit.field.frequency_type")
                    ),
                    sectionTitle: section,
                    cardIndex: cardIndex,
                    prescriptionIndex: prescriptionIndex
                ))
            }

            if MedicalPreSubmitValidationRules.isValidDecimalString(plan.doseValue) == false {
                issues.append(issue(
                    resourceType: .medicationPlan,
                    fieldPath: "\(pathPrefix).dose_value",
                    fieldKey: "\(pathPrefix).dose_value",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.dose_value"),
                    message: MedicalPreSubmitValidationRules.doseValueDecimalMessage(),
                    sectionTitle: section,
                    cardIndex: cardIndex,
                    prescriptionIndex: prescriptionIndex
                ))
            }
        }

        return issues
    }

    // MARK: - Medicine box

    private func validateMedicineBoxes(_ drafts: [MedicineBoxRecognitionDraft]) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let section = L10n.text("medical.upload.presubmit.section.medicine_box")

        for (index, box) in drafts.enumerated() {
            if MedicalPreSubmitValidationRules.isBlank(box.medicineName) {
                issues.append(issue(
                    resourceType: .medicineBox,
                    fieldPath: "medicine_boxes[\(index)].medicine_name",
                    fieldKey: "medicine_boxes[\(index)].medicine_name",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.medicine_name"),
                    message: MedicalPreSubmitValidationRules.indexedRequiredMessage(
                        index: index,
                        fieldLabel: L10n.text("medical.upload.presubmit.field.medicine_name")
                    ),
                    sectionTitle: section,
                    cardIndex: index
                ))
            }

            if MedicalPreSubmitValidationRules.requiresCompleteDateIfPresent(box.expireDate) == false {
                issues.append(dateIssue(
                    fieldPath: "medicine_boxes[\(index)].expire_date",
                    fieldKey: "medicine_boxes[\(index)].expire_date",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.expire_date"),
                    sectionTitle: section,
                    cardIndex: index
                ))
            }

            if MedicalPreSubmitValidationRules.isNonNegativeNumber(box.totalQuantity) == false {
                issues.append(issue(
                    resourceType: .medicineBox,
                    fieldPath: "medicine_boxes[\(index)].total_quantity",
                    fieldKey: "medicine_boxes[\(index)].total_quantity",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.total_quantity"),
                    message: MedicalPreSubmitValidationRules.validNumberMessage(),
                    sectionTitle: section,
                    cardIndex: index
                ))
            }
        }

        return issues
    }

    // MARK: - Builders

    private func issue(
        resourceType: MedicalPreSubmitValidationResourceType,
        fieldPath: String,
        fieldKey: String,
        fieldLabel: String,
        message: String,
        sectionTitle: String,
        cardIndex: Int? = nil,
        prescriptionIndex: Int? = nil
    ) -> MedicalPreSubmitValidationIssue {
        MedicalPreSubmitValidationIssue(
            resourceType: resourceType,
            fieldPath: fieldPath,
            fieldKey: fieldKey,
            fieldLabel: fieldLabel,
            message: message,
            sectionTitle: sectionTitle,
            cardIndex: cardIndex,
            prescriptionIndex: prescriptionIndex
        )
    }

    private func dateIssue(
        fieldPath: String,
        fieldKey: String,
        fieldLabel: String,
        sectionTitle: String,
        cardIndex: Int? = nil,
        prescriptionIndex: Int? = nil
    ) -> MedicalPreSubmitValidationIssue {
        issue(
            resourceType: resourceType(for: fieldPath),
            fieldPath: fieldPath,
            fieldKey: fieldKey,
            fieldLabel: fieldLabel,
            message: MedicalPreSubmitValidationRules.completeDateMessage(),
            sectionTitle: sectionTitle,
            cardIndex: cardIndex,
            prescriptionIndex: prescriptionIndex
        )
    }

    private func resourceType(for fieldPath: String) -> MedicalPreSubmitValidationResourceType {
        if fieldPath.hasPrefix("symptom") { return .symptom }
        if fieldPath.hasPrefix("visit") { return .visit }
        if fieldPath.hasPrefix("prescriptions") { return .prescription }
        if fieldPath.contains("medication_plans") || fieldPath.hasPrefix("medication_plans") { return .medicationPlan }
        if fieldPath.hasPrefix("medicine_boxes") { return .medicineBox }
        if fieldPath.hasPrefix("health_exam") { return .healthExamReport }
        if fieldPath.hasPrefix("examination_reports") { return .examinationReport }
        return .caseDocument
    }
}
