import Foundation

struct MedicalDocumentResultDetailNavigationContext {
    let memberID: Int
    let memberContextStore: MemberContextStore
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    let notificationClient: any NotificationClient
    let logger: Logger?

    init?(
        memberID: Int?,
        viewModel: MedicalDocumentUploadViewModel,
        logger: Logger? = nil
    ) {
        guard let memberID, let workflowAPI = viewModel.workflowAPIForCaseLocalForms else {
            return nil
        }
        self.memberID = memberID
        self.memberContextStore = viewModel.memberContextStoreForLocalForms
        self.workflowAPI = workflowAPI
        self.fileTransferService = viewModel.fileTransferServiceForResultDetails
        self.notificationClient = viewModel.notificationClientForLocalForms ?? MedicalDocumentResultNoopNotificationClient.shared
        self.logger = logger
    }
}

@MainActor
final class MedicalDocumentResultNoopNotificationClient: NotificationClient {
    static let shared = MedicalDocumentResultNoopNotificationClient()

    func publish(_ intent: NotificationIntent) {}
    func success(_ message: String, title: String?, source: String) {}
    func error(_ message: String, title: String?, source: String) {}
    func warning(_ message: String, title: String?, source: String) {}
    func info(_ message: String, title: String?, source: String) {}
}

extension MedicalReportRecognitionDraft {
    func remoteExaminationReport(memberID: Int, id: Int, medicalCaseID: Int? = nil) -> SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
        let performedAt = MedicalDateCoding.decodeDateOnlyOrDefaultNow(date, defaultDate: Date())
        return SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
            id: id,
            member: memberID,
            medicalRecord: medicalCaseID,
            category: category,
            subCategory: details.first?.subCategory,
            itemName: title,
            performedAt: performedAt,
            reportedAt: performedAt,
            organizationName: hospital,
            departmentName: nil,
            doctorName: doctor,
            findings: resolvedFindingsText,
            impression: resolvedImpressionText,
            source: nil,
            status: nil,
            extra: nil,
            createdAt: performedAt,
            updatedAt: Date(),
            attachments: [],
            medExamDetails: details.enumerated().map { pair in
                pair.element.remoteMedExamDetail(
                    memberID: memberID,
                    businessID: id,
                    id: id * 1000 + pair.offset,
                    sortOrder: pair.offset
                )
            }
        )
    }
}

extension ItemDraft {
    func remoteMedExamDetail(memberID: Int, businessID: Int, id: Int, sortOrder: Int) -> SparkMedicalSyncAPI.RemoteMedExamDetail {
        SparkMedicalSyncAPI.RemoteMedExamDetail(
            id: id,
            businessType: "examination",
            businessId: businessID,
            member: memberID,
            category: category ?? "",
            subCategory: subCategory ?? "",
            itemName: itemName?.nilIfBlank ?? category ?? "",
            itemCode: "",
            resultValue: resultValue?.nilIfBlank,
            unit: unit ?? "",
            referenceRange: referenceRange ?? "",
            flag: flag ?? "",
            resultAt: MedicalDateCoding.decodeDateOnlyOrDefaultNow(resultAt?.nilIfBlank, defaultDate: Date()),
            modality: modality ?? "",
            bodyPart: bodyPart ?? "",
            diagnosis: diagnosis?.nilIfBlank,
            extra: nil,
            sortOrder: sortOrder,
            updatedAt: Date()
        )
    }
}

extension MedicalReportItem {
    func remoteMedExamDetail(memberID: Int, businessID: Int, id: Int) -> SparkMedicalSyncAPI.RemoteMedExamDetail {
        SparkMedicalSyncAPI.RemoteMedExamDetail(
            id: id,
            businessType: "examination",
            businessId: businessID,
            member: memberID,
            category: category,
            subCategory: subCategory ?? "",
            itemName: itemName ?? category,
            itemCode: itemCode ?? "",
            resultValue: resultValue,
            unit: unit ?? "",
            referenceRange: referenceRange ?? "",
            flag: flag ?? "",
            resultAt: MedicalDateCoding.decodeDateOnlyOrDefaultNow(resultAt, defaultDate: Date()),
            modality: modality ?? "",
            bodyPart: bodyPart ?? "",
            diagnosis: diagnosis,
            extra: extra,
            sortOrder: sortOrder.parsedAsSortOrderInt() ?? 0,
            updatedAt: Date()
        )
    }
}

extension PrescriptionRecognitionDraft {
    func remotePrescription(memberID: Int, id: Int) -> SparkMedicalSyncAPI.RemotePrescription {
        SparkMedicalSyncAPI.RemotePrescription(
            id: id,
            member: memberID,
            medicalCase: medicalCase,
            prescriberName: prescriberName ?? "",
            institutionName: institutionName ?? "",
            prescribedAt: MedicalDateCoding.decodeDateOnlyOrDefaultNow(prescribedAt, defaultDate: Date()),
            diagnosis: diagnosis ?? "",
            prescriptionNo: prescriptionNo,
            status: status ?? "active",
            extra: extra,
            attachments: [],
            updatedAt: Date()
        )
    }
}

extension MedicationPlanRecognitionDraft {
    func remoteMedicineBox(memberID: Int, id: Int) -> SparkMedicalSyncAPI.RemoteMedicineBox {
        let box = medicineBox
        return SparkMedicalSyncAPI.RemoteMedicineBox(
            id: id,
            member: memberID,
            medicineName: medicineName ?? box?.medicineName ?? brandName ?? "未命名药品",
            medicineType: medicineType ?? box?.medicineType,
            brandName: brandName ?? box?.brandName ?? "",
            dosageForm: dosageForm ?? box?.dosageForm ?? "",
            strength: strength ?? box?.strength ?? "",
            doseUnit: doseUnit ?? box?.doseUnit ?? "",
            totalQuantity: (totalQuantity ?? box?.totalQuantity).parsedAsTotalQuantity(),
            expireDate: MedicalDateCoding.decodeDateOnlyOrDefaultNow(expireDate ?? box?.expireDate, defaultDate: Date()),
            notes: box?.notes ?? instructions ?? "",
            extra: extra ?? box?.extra,
            attachments: [],
            updatedAt: Date()
        )
    }

    func remoteMedicationPlan(memberID: Int, id: Int, prescriptionID: Int? = nil, medicineBoxID: Int? = nil, medicalCaseID: Int? = nil) -> SparkMedicalSyncAPI.RemoteMedicationPlan {
        SparkMedicalSyncAPI.RemoteMedicationPlan(
            id: id,
            member: memberID,
            medicalCase: medicalCaseID,
            medicineBox: medicineBoxID,
            prescription: prescriptionID,
            drugName: medicineName ?? medicineBox?.medicineName ?? brandName ?? "未命名药品",
            dosePerTime: dosePerTime ?? "",
            doseValue: doseValue.parsedAsDoseValue(),
            doseUnit: doseUnit ?? "",
            frequencyType: frequencyType ?? "daily",
            everyNDays: everyNDays.parsedAsAgeAtVisitInteger(),
            weeklyWeekdays: weeklyWeekdays ?? [],
            frequencyText: frequencyText ?? "",
            reminderTimes: CodableReminderTimesList(wrappedValue: .normalized(from: reminderTimes)),
            startDate: MedicalDateCoding.decodeDateOnlyOrDefaultNow(startDate, defaultDate: Date()),
            endDate: endDate.flatMap { MedicalDateCoding.decodeDateOnlyOrDefaultNow($0, defaultDate: Date()) },
            instructions: instructions ?? "",
            reminderEnabled: reminderEnabled ?? false,
            status: status ?? "active",
            extra: extra,
            attachments: [],
            updatedAt: Date()
        )
    }
}

extension MedicationPlanDraft {
    init(recognition: MedicationPlanRecognitionDraft) {
        self.init()
        medicalCaseID = nil
        medicineBoxID = nil
        prescriptionID = nil
        drugName = recognition.medicineName ?? recognition.medicineBox?.medicineName ?? recognition.brandName ?? ""
        dosePerTime = recognition.dosePerTime ?? ""
        doseValue = recognition.doseValue ?? ""
        doseUnit = recognition.doseUnit ?? "片"
        reminderFrequencyType = MedicationReminderFrequencyType(rawValue: recognition.frequencyType ?? "daily") ?? .daily
        everyNDays = recognition.everyNDays.parsedAsAgeAtVisitInteger() ?? 1
        weeklyWeekdays = Set((recognition.weeklyWeekdays ?? []).filter { (1...7).contains($0) })
        frequencyText = recognition.frequencyText ?? ""
        reminderTimesText = (recognition.reminderTimes ?? []).map(\.time).joined(separator: ", ")
        startDate = MedicalDateCoding.decodeDateOnlyOrDefaultNow(recognition.startDate, defaultDate: Date())
        if let endDate = recognition.endDate?.nilIfBlank {
            hasEndDate = true
            self.endDate = MedicalDateCoding.decodeDateOnlyOrDefaultNow(endDate, defaultDate: Date())
        }
        instructions = recognition.instructions ?? ""
        reminderEnabled = recognition.reminderEnabled ?? true
        status = recognition.status ?? "active"
    }

    func recognitionDraft(preserving existing: MedicationPlanRecognitionDraft) -> MedicationPlanRecognitionDraft {
        let separators = CharacterSet(charactersIn: ",，\n;；")
        let timeTokens = reminderTimesText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let optionalDoseValue: String? = doseValue.isEmpty ? nil : doseValue
        let parsedDose = optionalDoseValue.parsedAsDoseValue()
        var parsedReminderTimes: [ReminderTime] = []
        parsedReminderTimes.reserveCapacity(timeTokens.count)
        for token in timeTokens {
            parsedReminderTimes.append(ReminderTime(time: token, dose: parsedDose))
        }

        return MedicationPlanRecognitionDraft(
            medicineName: drugName.nilIfBlank,
            medicineType: existing.medicineType,
            totalQuantity: existing.totalQuantity,
            expireDate: existing.expireDate,
            medicineBox: existing.medicineBox,
            brandName: existing.brandName,
            dosageForm: existing.dosageForm,
            strength: existing.strength,
            dosePerTime: dosePerTime.nilIfBlank,
            doseValue: doseValue.nilIfBlank,
            doseUnit: doseUnit.nilIfBlank,
            frequencyType: reminderFrequencyType.rawValue,
            everyNDays: "\(everyNDays)",
            weeklyWeekdays: Array(weeklyWeekdays).sorted(),
            frequencyText: resolvedFrequencyText.nilIfBlank,
            startDate: MedicalDateCoding.encodeDateOnly(startDate),
            endDate: hasEndDate ? MedicalDateCoding.encodeDateOnly(endDate) : nil,
            instructions: instructions.nilIfBlank,
            reminderEnabled: reminderEnabled,
            reminderTimes: parsedReminderTimes,
            sortOrder: existing.sortOrder,
            extra: existing.extra,
            attachmentFileIds: existing.attachmentFileIds
        )
    }
}
