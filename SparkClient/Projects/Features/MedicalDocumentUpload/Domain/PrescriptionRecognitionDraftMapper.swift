import Foundation

enum MedicationPrescriptionDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum MedicationPlanDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum MedicineBoxDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum ExaminationReportDetailMode: Equatable, Sendable {
    case server
    case localDraft
}

enum PrescriptionRecognitionDraftMapper {
    static let medicineBoxUnlinkedExtraKey = "medicine_box_unlinked"
    static let confirmedMedicineBoxIDExtraKey = "confirmed_medicine_box_id"

    static func isMedicineBoxUnlinked(_ draft: MedicationPlanRecognitionDraft) -> Bool {
        draft.extra?[medicineBoxUnlinkedExtraKey] == "true"
    }

    static func temporaryPrescriptionID(prescriptionIndex: Int) -> Int {
        -20_000 - prescriptionIndex
    }

    static func temporaryMedicineBoxID(prescriptionIndex: Int, medicationIndex: Int) -> Int {
        -30_000 - prescriptionIndex * 100 - medicationIndex
    }

    static func temporaryMedicineBoxRecognitionID(index: Int) -> Int {
        -50_000 - index
    }

    static func temporaryStandaloneMedicineBoxID(index: Int) -> Int {
        -35_000 - index
    }

    static func temporaryStandalonePlanID(index: Int) -> Int {
        -45_000 - index
    }

    static func temporaryExaminationReportID(index: Int) -> Int {
        -10_000 - index
    }

    static func temporaryPlanID(prescriptionIndex: Int, medicationIndex: Int) -> Int {
        -40_000 - prescriptionIndex * 100 - medicationIndex
    }

    static func remotePrescription(
        from batch: PrescriptionRecognitionDraft,
        memberID: Int,
        prescriptionIndex: Int
    ) -> SparkMedicalSyncAPI.RemotePrescription {
        batch.remotePrescription(
            memberID: memberID,
            id: temporaryPrescriptionID(prescriptionIndex: prescriptionIndex)
        )
    }

    static func remoteMedicineBoxes(
        from batch: PrescriptionRecognitionDraft,
        memberID: Int,
        prescriptionIndex: Int
    ) -> [SparkMedicalSyncAPI.RemoteMedicineBox] {
        (batch.medicationPlans ?? []).enumerated().map { pair in
            pair.element.remoteMedicineBox(
                memberID: memberID,
                id: temporaryMedicineBoxID(prescriptionIndex: prescriptionIndex, medicationIndex: pair.offset)
            )
        }
    }

    static func remoteMedicationPlans(
        from batch: PrescriptionRecognitionDraft,
        memberID: Int,
        prescriptionIndex: Int,
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox]
    ) -> [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        (batch.medicationPlans ?? []).enumerated().map { pair in
            let boxID: Int? = isMedicineBoxUnlinked(pair.element)
                ? nil
                : (medicineBoxes.indices.contains(pair.offset) ? medicineBoxes[pair.offset].id : nil)
            return pair.element.remoteMedicationPlan(
                memberID: memberID,
                id: temporaryPlanID(prescriptionIndex: prescriptionIndex, medicationIndex: pair.offset),
                prescriptionID: temporaryPrescriptionID(prescriptionIndex: prescriptionIndex),
                medicineBoxID: boxID,
                medicalCaseID: batch.medicalCase
            )
        }
    }

    static func prescriptionDraft(
        from prescription: SparkMedicalSyncAPI.RemotePrescription,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox],
        preserving existing: PrescriptionRecognitionDraft?
    ) -> PrescriptionRecognitionDraft {
        let medicationDrafts = plans.enumerated().map { index, plan in
            let box = plan.medicineBox.flatMap { medicineBoxesByID[$0] }
            let existingPlan = existing?.medicationPlans?[safe: index]
            return medicationPlanDraft(from: plan, box: box, preserving: existingPlan)
        }
        return PrescriptionRecognitionDraft(
            medicalCase: prescription.medicalCase ?? existing?.medicalCase,
            prescriberName: prescription.prescriberName.nilIfBlank ?? existing?.prescriberName,
            institutionName: prescription.institutionName.nilIfBlank ?? existing?.institutionName,
            prescribedAt: prescription.prescribedAt.map { MedicalDateCoding.encodeDateOnly($0) } ?? existing?.prescribedAt,
            diagnosis: prescription.diagnosis.nilIfBlank ?? existing?.diagnosis,
            prescriptionNo: prescription.prescriptionNo ?? existing?.prescriptionNo,
            status: prescription.status.nilIfBlank ?? existing?.status,
            extra: prescription.extra ?? existing?.extra,
            medicationPlans: medicationDrafts,
            attachmentFileIds: existing?.attachmentFileIds ?? []
        )
    }

    static func medicationPlanDraftClearedMedicineBox(
        from draft: MedicationPlanRecognitionDraft
    ) -> MedicationPlanRecognitionDraft {
        var extra = draft.extra ?? [:]
        extra[medicineBoxUnlinkedExtraKey] = "true"
        return MedicationPlanRecognitionDraft(
            medicineName: draft.medicineName,
            medicineType: draft.medicineType,
            totalQuantity: draft.totalQuantity,
            expireDate: draft.expireDate,
            medicineBox: nil,
            brandName: draft.brandName,
            dosageForm: draft.dosageForm,
            strength: draft.strength,
            dosePerTime: draft.dosePerTime,
            doseValue: draft.doseValue,
            doseUnit: draft.doseUnit,
            frequencyType: draft.frequencyType,
            everyNDays: draft.everyNDays,
            weeklyWeekdays: draft.weeklyWeekdays,
            frequencyText: draft.frequencyText,
            startDate: draft.startDate,
            endDate: draft.endDate,
            instructions: draft.instructions,
            reminderEnabled: draft.reminderEnabled,
            reminderTimes: draft.reminderTimes,
            status: draft.status,
            sortOrder: draft.sortOrder,
            extra: extra,
            attachmentFileIds: draft.attachmentFileIds
        )
    }

    static func remoteMedicationPlan(
        from draft: MedicationPlanRecognitionDraft,
        preserving plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxID: Int?
    ) -> SparkMedicalSyncAPI.RemoteMedicationPlan {
        draft.remoteMedicationPlan(
            memberID: plan.member,
            id: plan.id,
            prescriptionID: plan.prescription,
            medicineBoxID: medicineBoxID,
            medicalCaseID: plan.medicalCase
        )
    }

    static func medicationPlanDraft(
        from plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        box: SparkMedicalSyncAPI.RemoteMedicineBox?,
        preserving existing: MedicationPlanRecognitionDraft?
    ) -> MedicationPlanRecognitionDraft {
        let seed = existing ?? MedicationPlanRecognitionDraft()
        var draft = MedicationPlanDraft(existing: plan).recognitionDraft(preserving: seed)
        if let box {
            draft = applyMedicineBox(box, to: draft, preservingAttachmentIDs: existing?.attachmentFileIds ?? draft.attachmentFileIds)
        }
        return draft
    }

    static func medicineBoxDraft(from box: SparkMedicalSyncAPI.RemoteMedicineBox) -> MedicineBoxRecognitionDraft {
        MedicineBoxDraft(existing: box).recognitionDraft()
    }

    static func applyMedicineBox(
        _ box: SparkMedicalSyncAPI.RemoteMedicineBox,
        to plan: MedicationPlanRecognitionDraft,
        preservingAttachmentIDs: [UUID]
    ) -> MedicationPlanRecognitionDraft {
        let boxDraft = medicineBoxDraft(from: box)
        var mergedExtra = plan.extra ?? [:]
        mergedExtra.removeValue(forKey: medicineBoxUnlinkedExtraKey)
        return MedicationPlanRecognitionDraft(
            medicineName: box.medicineName.nilIfBlank ?? plan.medicineName,
            medicineType: box.medicineType ?? plan.medicineType,
            totalQuantity: box.totalQuantity.map {
                $0.formatted(.number.precision(.fractionLength(0...2)))
            } ?? plan.totalQuantity,
            expireDate: box.expireDate.map { MedicalDateCoding.encodeDateOnly($0) } ?? plan.expireDate,
            medicineBox: boxDraft,
            brandName: box.brandName.nilIfBlank ?? plan.brandName,
            dosageForm: box.dosageForm.nilIfBlank ?? plan.dosageForm,
            strength: box.strength.nilIfBlank ?? plan.strength,
            dosePerTime: plan.dosePerTime,
            doseValue: plan.doseValue,
            doseUnit: box.doseUnit.nilIfBlank ?? plan.doseUnit,
            frequencyType: plan.frequencyType,
            everyNDays: plan.everyNDays,
            weeklyWeekdays: plan.weeklyWeekdays,
            frequencyText: plan.frequencyText,
            startDate: plan.startDate,
            endDate: plan.endDate,
            instructions: plan.instructions,
            reminderEnabled: plan.reminderEnabled,
            reminderTimes: plan.reminderTimes,
            status: plan.status,
            sortOrder: plan.sortOrder,
            extra: mergedExtra,
            attachmentFileIds: preservingAttachmentIDs
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element == PrescriptionRecognitionDraft {
    var associatedAttachmentFileIDs: Set<UUID> {
        reduce(into: Set<UUID>()) { result, batch in
            result.formUnion(batch.associatedAttachmentFileIDs)
        }
    }

    func resolvingMedicineBoxCandidates(
        confirmations: [MedicationCandidateKey: MedicineBoxCandidateConfirmation]
    ) -> [PrescriptionRecognitionDraft] {
        enumerated().map { prescriptionIndex, batch in
            var updatedBatch = batch
            updatedBatch.medicationPlans = (batch.medicationPlans ?? []).enumerated().map { medicationIndex, plan in
                let key = MedicationCandidateKey(
                    prescriptionIndex: prescriptionIndex,
                    medicationIndex: medicationIndex
                )
                return plan.applyingMedicineBoxCandidateConfirmation(confirmations[key] ?? .default)
            }
            return updatedBatch
        }
    }
}

extension MedicationPlanRecognitionDraft {
    func applyingMedicineBoxCandidateConfirmation(
        _ confirmation: MedicineBoxCandidateConfirmation
    ) -> MedicationPlanRecognitionDraft {
        if PrescriptionRecognitionDraftMapper.isMedicineBoxUnlinked(self) {
            return self
        }

        var extra = extra ?? [:]
        extra.removeValue(forKey: PrescriptionRecognitionDraftMapper.confirmedMedicineBoxIDExtraKey)

        guard confirmation.isConfirmed else {
            return PrescriptionRecognitionDraftMapper.medicationPlanDraftClearedMedicineBox(from: self)
                .strippingConfirmedMedicineBoxID()
        }

        switch confirmation.action {
        case .bindExisting(let medicineBoxID):
            let stripped = PrescriptionRecognitionDraftMapper.medicationPlanDraftClearedMedicineBox(from: self)
            var bindExtra = stripped.extra ?? [:]
            bindExtra.removeValue(forKey: PrescriptionRecognitionDraftMapper.medicineBoxUnlinkedExtraKey)
            bindExtra[PrescriptionRecognitionDraftMapper.confirmedMedicineBoxIDExtraKey] = "\(medicineBoxID)"
            return MedicationPlanRecognitionDraft(
                medicineName: stripped.medicineName,
                medicineType: stripped.medicineType,
                totalQuantity: stripped.totalQuantity,
                expireDate: stripped.expireDate,
                medicineBox: nil,
                brandName: stripped.brandName,
                dosageForm: stripped.dosageForm,
                strength: stripped.strength,
                dosePerTime: stripped.dosePerTime,
                doseValue: stripped.doseValue,
                doseUnit: stripped.doseUnit,
                frequencyType: stripped.frequencyType,
                everyNDays: stripped.everyNDays,
                weeklyWeekdays: stripped.weeklyWeekdays,
                frequencyText: stripped.frequencyText,
                startDate: stripped.startDate,
                endDate: stripped.endDate,
                instructions: stripped.instructions,
                reminderEnabled: stripped.reminderEnabled,
                reminderTimes: stripped.reminderTimes,
                status: stripped.status,
                sortOrder: stripped.sortOrder,
                extra: bindExtra,
                attachmentFileIds: stripped.attachmentFileIds
            )
        case .createNew:
            var createExtra = extra
            createExtra.removeValue(forKey: PrescriptionRecognitionDraftMapper.medicineBoxUnlinkedExtraKey)
            var resolved = self
            if let edited = confirmation.editedCandidate {
                resolved = resolved.updatingMedicineBoxCandidate(edited)
            }
            return MedicationPlanRecognitionDraft(
                medicineName: resolved.medicineName,
                medicineType: resolved.medicineType,
                totalQuantity: resolved.totalQuantity,
                expireDate: resolved.expireDate,
                medicineBox: resolved.medicineBox,
                brandName: resolved.brandName,
                dosageForm: resolved.dosageForm,
                strength: resolved.strength,
                dosePerTime: resolved.dosePerTime,
                doseValue: resolved.doseValue,
                doseUnit: resolved.doseUnit,
                frequencyType: resolved.frequencyType,
                everyNDays: resolved.everyNDays,
                weeklyWeekdays: resolved.weeklyWeekdays,
                frequencyText: resolved.frequencyText,
                startDate: resolved.startDate,
                endDate: resolved.endDate,
                instructions: resolved.instructions,
                reminderEnabled: resolved.reminderEnabled,
                reminderTimes: resolved.reminderTimes,
                status: resolved.status,
                sortOrder: resolved.sortOrder,
                extra: createExtra,
                attachmentFileIds: resolved.attachmentFileIds
            )
        case .none:
            return PrescriptionRecognitionDraftMapper.medicationPlanDraftClearedMedicineBox(from: self)
                .strippingConfirmedMedicineBoxID()
        }
    }

    func updatingMedicineBoxCandidate(_ candidate: MedicineBoxRecognitionDraft) -> MedicationPlanRecognitionDraft {
        MedicationPlanRecognitionDraft(
            medicineName: candidate.medicineName?.nilIfBlank ?? medicineName,
            medicineType: candidate.medicineType ?? medicineType,
            totalQuantity: candidate.totalQuantity ?? totalQuantity,
            expireDate: candidate.expireDate ?? expireDate,
            medicineBox: candidate,
            brandName: candidate.brandName ?? brandName,
            dosageForm: candidate.dosageForm ?? dosageForm,
            strength: candidate.strength ?? strength,
            dosePerTime: dosePerTime,
            doseValue: doseValue,
            doseUnit: candidate.doseUnit ?? doseUnit,
            frequencyType: frequencyType,
            everyNDays: everyNDays,
            weeklyWeekdays: weeklyWeekdays,
            frequencyText: frequencyText,
            startDate: startDate,
            endDate: endDate,
            instructions: instructions,
            reminderEnabled: reminderEnabled,
            reminderTimes: reminderTimes,
            status: status,
            sortOrder: sortOrder,
            extra: extra,
            attachmentFileIds: attachmentFileIds
        )
    }

    fileprivate func strippingConfirmedMedicineBoxID() -> MedicationPlanRecognitionDraft {
        var cleanedExtra = extra ?? [:]
        cleanedExtra.removeValue(forKey: PrescriptionRecognitionDraftMapper.confirmedMedicineBoxIDExtraKey)
        return MedicationPlanRecognitionDraft(
            medicineName: medicineName,
            medicineType: medicineType,
            totalQuantity: totalQuantity,
            expireDate: expireDate,
            medicineBox: medicineBox,
            brandName: brandName,
            dosageForm: dosageForm,
            strength: strength,
            dosePerTime: dosePerTime,
            doseValue: doseValue,
            doseUnit: doseUnit,
            frequencyType: frequencyType,
            everyNDays: everyNDays,
            weeklyWeekdays: weeklyWeekdays,
            frequencyText: frequencyText,
            startDate: startDate,
            endDate: endDate,
            instructions: instructions,
            reminderEnabled: reminderEnabled,
            reminderTimes: reminderTimes,
            status: status,
            sortOrder: sortOrder,
            extra: cleanedExtra,
            attachmentFileIds: attachmentFileIds
        )
    }
}

extension MedicineBoxRecognitionDraft {
    func remoteMedicineBox(memberID: Int, id: Int) -> SparkMedicalSyncAPI.RemoteMedicineBox {
        MedicationPlanRecognitionDraft(
            medicineName: medicineName,
            medicineType: medicineType,
            medicineBox: self,
            brandName: brandName,
            dosageForm: dosageForm,
            strength: strength,
            doseUnit: doseUnit
        ).remoteMedicineBox(memberID: memberID, id: id)
    }
}
