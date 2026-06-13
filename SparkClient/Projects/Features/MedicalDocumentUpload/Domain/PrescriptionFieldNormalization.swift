import Foundation

enum PrescriptionLifecycleStatus: String, CaseIterable, Sendable {
    case active
    case completed
    case cancelled

    static let allRawValues: Set<String> = Set(allCases.map(\.rawValue))

    static func displayLabel(for rawValue: String) -> String {
        switch rawValue {
        case Self.active.rawValue:
            return L10n.text("home.medical.prescription.status.active")
        case Self.completed.rawValue:
            return L10n.text("home.medical.prescription.status.completed")
        case Self.cancelled.rawValue:
            return L10n.text("home.medical.prescription.status.cancelled")
        default:
            return rawValue
        }
    }
}

enum MedicationPlanLifecycleStatus: String, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case cancelled

    static let allRawValues: Set<String> = Set(allCases.map(\.rawValue))
}

enum PrescriptionFieldNormalization {
    static let prescriptionTypeExtraKey = "prescriptionTypeText"
    static let paymentStatusExtraKey = "paymentStatusText"
    static let rawStatusExtraKey = "rawStatusText"

    private static let prescriptionTypeTexts: Set<String> = [
        "普通", "门诊", "急诊", "医保", "自费",
        "outpatient", "emergency", "general",
    ]

    private static let paymentStatusTexts: Set<String> = [
        "paid", "已支付", "支付", "unpaid", "未支付", "待支付", "未付",
        "refunded", "已退费", "退费",
    ]

    struct PrescriptionStatusNormalizationResult: Sendable {
        var status: String
        var extraUpdates: [String: String]
    }

    static func normalizePrescriptionDraft(_ draft: PrescriptionRecognitionDraft) -> PrescriptionRecognitionDraft {
        let statusResult = normalizePrescriptionStatus(draft.status, extra: draft.extra)

        let plans = (draft.medicationPlans ?? []).enumerated().map { index, plan in
            var next = normalizeMedicationPlanDraft(plan)
            if next.sortOrder?.nilIfBlank == nil {
                next.sortOrder = String(index)
            }
            return next
        }

        var mergedExtra = draft.extra ?? [:]
        for (key, value) in statusResult.extraUpdates {
            mergedExtra[key] = value
        }

        return PrescriptionRecognitionDraft(
            medicalCase: draft.medicalCase,
            prescriberName: draft.prescriberName,
            institutionName: draft.institutionName,
            prescribedAt: draft.prescribedAt,
            diagnosis: draft.diagnosis,
            prescriptionNo: draft.prescriptionNo,
            status: statusResult.status,
            extra: mergedExtra.isEmpty ? nil : mergedExtra,
            medicationPlans: plans,
            attachmentFileIds: draft.attachmentFileIds
        )
    }

    static func normalizeMedicationPlanDraft(_ draft: MedicationPlanRecognitionDraft) -> MedicationPlanRecognitionDraft {
        MedicationPlanRecognitionDraft(
            medicineName: draft.medicineName,
            medicineType: draft.medicineType,
            totalQuantity: draft.totalQuantity,
            expireDate: draft.expireDate,
            medicineBox: draft.medicineBox,
            brandName: draft.brandName,
            dosageForm: draft.dosageForm,
            strength: draft.strength,
            dosePerTime: draft.dosePerTime,
            doseValue: draft.doseValue,
            doseUnit: draft.doseUnit,
            frequencyType: normalizeFrequencyType(draft.frequencyType),
            everyNDays: draft.everyNDays,
            weeklyWeekdays: draft.weeklyWeekdays,
            frequencyText: draft.frequencyText,
            startDate: draft.startDate,
            endDate: draft.endDate,
            instructions: draft.instructions,
            reminderEnabled: draft.reminderEnabled,
            reminderTimes: .normalized(from: draft.reminderTimes),
            status: normalizeMedicationPlanStatus(draft.status),
            sortOrder: draft.sortOrder,
            extra: draft.extra,
            attachmentFileIds: draft.attachmentFileIds
        )
    }

    static func normalizePrescriptionStatus(
        _ raw: String?,
        extra: [String: String]?
    ) -> PrescriptionStatusNormalizationResult {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        var extraUpdates: [String: String] = [:]

        guard let trimmed, trimmed.isEmpty == false else {
            return PrescriptionStatusNormalizationResult(
                status: PrescriptionLifecycleStatus.active.rawValue,
                extraUpdates: extraUpdates
            )
        }

        let normalized = trimmed.lowercased()

        if PrescriptionLifecycleStatus.allRawValues.contains(normalized) {
            return PrescriptionStatusNormalizationResult(
                status: normalized,
                extraUpdates: extraUpdates
            )
        }

        if isPaymentStatusText(trimmed, normalized: normalized) {
            extraUpdates[paymentStatusExtraKey] = trimmed
            extraUpdates[rawStatusExtraKey] = trimmed
            return PrescriptionStatusNormalizationResult(
                status: PrescriptionLifecycleStatus.active.rawValue,
                extraUpdates: extraUpdates
            )
        }

        if isPrescriptionTypeText(trimmed, normalized: normalized) {
            extraUpdates[prescriptionTypeExtraKey] = trimmed
            extraUpdates[rawStatusExtraKey] = trimmed
            return PrescriptionStatusNormalizationResult(
                status: PrescriptionLifecycleStatus.active.rawValue,
                extraUpdates: extraUpdates
            )
        }

        extraUpdates[rawStatusExtraKey] = trimmed
        return PrescriptionStatusNormalizationResult(
            status: PrescriptionLifecycleStatus.active.rawValue,
            extraUpdates: extraUpdates
        )
    }

    static func normalizeMedicationPlanStatus(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false else {
            return MedicationPlanLifecycleStatus.active.rawValue
        }

        let normalized = trimmed.lowercased()
        if MedicationPlanLifecycleStatus.allRawValues.contains(normalized) {
            return normalized
        }

        switch normalized {
        case "执行中", "生效", "有效", "进行中":
            return MedicationPlanLifecycleStatus.active.rawValue
        default:
            return trimmed
        }
    }

    static func normalizeFrequencyType(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "every_n_days", "interval", "间隔":
            return MedicationReminderFrequencyType.everyNDays.rawValue
        case "weekly", "week", "每周":
            return MedicationReminderFrequencyType.weekly.rawValue
        case "daily", "day", "每天", nil, "":
            return MedicationReminderFrequencyType.daily.rawValue
        default:
            return raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ?? MedicationReminderFrequencyType.daily.rawValue
        }
    }

    static func resolvedLifecycleStatus(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let trimmed, PrescriptionLifecycleStatus.allRawValues.contains(trimmed) else {
            return PrescriptionLifecycleStatus.active.rawValue
        }
        return trimmed
    }

    private static func isPaymentStatusText(_ trimmed: String, normalized: String) -> Bool {
        paymentStatusTexts.contains(trimmed) || paymentStatusTexts.contains(normalized)
    }

    private static func isPrescriptionTypeText(_ trimmed: String, normalized: String) -> Bool {
        prescriptionTypeTexts.contains(trimmed)
            || prescriptionTypeTexts.contains(normalized)
            || ["有效", "已开具", "draft", "dispensed"].contains(normalized)
    }
}

struct PrescriptionPayloadPreflightError: Error, Sendable {
    let issues: [MedicalPreSubmitValidationIssue]

    var localizedDescription: String {
        L10n.text("medical.upload.presubmit.error.save_blocked")
    }
}

enum PrescriptionPayloadPreflightValidator {
    static func validate(prescriptions: [PrescriptionCreateRequest]) -> [MedicalPreSubmitValidationIssue] {
        var issues: [MedicalPreSubmitValidationIssue] = []
        let section = L10n.text("medical.upload.presubmit.section.prescription")
        let medicationSection = L10n.text("medical.upload.presubmit.section.medication")

        for (prescriptionIndex, prescription) in prescriptions.enumerated() {
            if MedicalPreSubmitValidationRules.isValidPrescriptionStatus(prescription.status) == false {
                issues.append(makeIssue(
                    resourceType: .prescription,
                    fieldPath: "prescriptions[\(prescriptionIndex)].status",
                    fieldKey: "prescriptions[\(prescriptionIndex)].status",
                    fieldLabel: L10n.text("medical.upload.presubmit.field.prescription_status"),
                    message: MedicalPreSubmitValidationRules.prescriptionStatusMessage(),
                    sectionTitle: section,
                    cardIndex: prescriptionIndex
                ))
            }

            for (planIndex, plan) in prescription.medicationPlans.enumerated() {
                let pathPrefix = "prescriptions[\(prescriptionIndex)].medication_plans[\(planIndex)]"

                if MedicalPreSubmitValidationRules.isValidMedicationPlanStatus(plan.status) == false {
                    issues.append(makeIssue(
                        resourceType: .medicationPlan,
                        fieldPath: "\(pathPrefix).status",
                        fieldKey: "\(pathPrefix).status",
                        fieldLabel: L10n.text("medical.upload.presubmit.field.medication_plan_status"),
                        message: MedicalPreSubmitValidationRules.medicationPlanStatusMessage(),
                        sectionTitle: medicationSection,
                        cardIndex: planIndex,
                        prescriptionIndex: prescriptionIndex
                    ))
                }

                if MedicalPreSubmitValidationRules.isValidFrequencyType(plan.frequencyType) == false {
                    issues.append(makeIssue(
                        resourceType: .medicationPlan,
                        fieldPath: "\(pathPrefix).frequency_type",
                        fieldKey: "\(pathPrefix).frequency_type",
                        fieldLabel: L10n.text("medical.upload.presubmit.field.frequency_type"),
                        message: MedicalPreSubmitValidationRules.validEnumMessage(
                            fieldLabel: L10n.text("medical.upload.presubmit.field.frequency_type")
                        ),
                        sectionTitle: medicationSection,
                        cardIndex: planIndex,
                        prescriptionIndex: prescriptionIndex
                    ))
                }

                if plan.medicineBoxID != nil && plan.medicineBox != nil {
                    issues.append(makeIssue(
                        resourceType: .medicationPlan,
                        fieldPath: "\(pathPrefix).medicine_box",
                        fieldKey: "\(pathPrefix).medicine_box",
                        fieldLabel: L10n.text("medical.upload.presubmit.field.medicine_box_binding"),
                        message: MedicalPreSubmitValidationRules.medicineBoxBindingConflictMessage(),
                        sectionTitle: medicationSection,
                        cardIndex: planIndex,
                        prescriptionIndex: prescriptionIndex
                    ))
                }
            }
        }

        return issues
    }

    private static func makeIssue(
        resourceType: MedicalPreSubmitValidationResourceType,
        fieldPath: String,
        fieldKey: String,
        fieldLabel: String,
        message: String,
        sectionTitle: String,
        cardIndex: Int?,
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
}
