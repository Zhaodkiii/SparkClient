import Foundation

extension SparkMedicalMemberAPI.RemoteMember {
    var domainModel: Member {
        Member(
            id: id,
            name: name,
            gender: gender,
            relationship: relationship ?? "self",
            birthDate: birthDate,
            bloodType: bloodType,
            allergies: allergies,
            chronicConditions: chronicConditions,
            notes: notes,
            avatarUrl: avatarUrl,
            isPrimary: isPrimary,
            updatedAt: updatedAt,
            binding: bindingInfo
        )
    }
}

extension SparkMedicalMemberAPI.MemberDetailResponse {
    var domainMember: Member {
        Member(
            id: id,
            name: name,
            gender: gender,
            relationship: relationship,
            birthDate: birthDate,
            bloodType: bloodType,
            allergies: allergies,
            chronicConditions: chronicConditions,
            notes: notes,
            avatarUrl: avatarUrl,
            isPrimary: isPrimary,
            updatedAt: updatedAt,
            binding: MemberBindingInfo(
                bindingID: bindingId,
                role: bindingRole,
                sharedUserCount: sharedUserCount,
                canShare: canShare,
                canEdit: canEdit,
                canDelete: canDelete,
                canUnbind: canUnbind
            )
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMember {
    var domainModel: Member {
        Member(
            id: id,
            name: name,
            gender: gender,
            relationship: relationship ?? "self",
            birthDate: birthDate,
            bloodType: bloodType,
            allergies: allergies,
            chronicConditions: chronicConditions,
            notes: notes,
            avatarUrl: avatarUrl,
            isPrimary: isPrimary,
            updatedAt: updatedAt,
            binding: bindingInfo
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicalCaseSummary {
    var domainModel: MedicalCase {
        MedicalCase(
            id: id,
            memberID: member,
            recordType: recordType ?? "",
            status: status ?? 0,
            title: title ?? "",
            hospitalName: hospitalName ?? "",
            ageAtVisit: ageAtVisit,
            severity: severity,
            caseStatus: caseStatus,
            diagnosisSummary: diagnosisSummary ?? "",
            extra: extra ?? [:],
            updatedAt: updatedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

extension SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments {
    var domainModel: HealthExamReport {
        HealthExamReport(
            id: id,
            memberID: member,
            institutionName: institutionName ?? "",
            reportNo: reportNo ?? "",
            examDate: examDate,
            examType: examType ?? 0,
            summary: summary,
            source: source ?? 0,
            rawOCR: nil,
            status: status ?? 0,
            extra: extra,
            updatedAt: updatedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

extension SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
    var domainModel: ExaminationReport {
        ExaminationReport(
            id: id,
            memberID: member,
            medicalRecordID: medicalRecord,
            category: category ?? "",
            subCategory: subCategory ?? "",
            itemName: itemName ?? "",
            performedAt: performedAt,
            reportedAt: reportedAt,
            organizationName: organizationName ?? "",
            departmentName: departmentName ?? "",
            doctorName: doctorName ?? "",
            findings: findings,
            impression: impression,
            source: source ?? 0,
            rawOCR: nil,
            status: status ?? 0,
            extra: extra,
            updatedAt: updatedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicineBox {
    var domainModel: MedicineBox {
        MedicineBox(
            id: id,
            memberID: member,
            medicineName: medicineName,
            medicineType: medicineType,
            brandName: brandName,
            dosageForm: dosageForm,
            strength: strength,
            doseUnit: doseUnit,
            totalQuantity: totalQuantity,
            expireDate: expireDate,
            notes: notes,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemotePrescription {
    var domainModel: Prescription {
        Prescription(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            prescriberName: prescriberName,
            institutionName: institutionName,
            prescribedAt: prescribedAt,
            diagnosis: diagnosis,
            prescriptionNo: prescriptionNo,
            status: status,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicationPlan {
    var domainModel: MedicationPlan {
        MedicationPlan(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            medicineBoxID: medicineBox,
            prescriptionID: prescription,
            drugName: drugName,
            dosePerTime: dosePerTime,
            doseValue: doseValue,
            doseUnit: doseUnit,
            frequencyType: frequencyType,
            everyNDays: everyNDays,
            weeklyWeekdays: weeklyWeekdays,
            frequencyText: frequencyText,
            reminderTimes: reminderTimes,
            startDate: startDate,
            endDate: endDate,
            instructions: instructions,
            reminderEnabled: reminderEnabled,
            status: status,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicationRecord {
    var domainModel: MedicationRecord {
        MedicationRecord(
            id: id,
            memberID: member,
            planID: plan,
            scheduledAt: scheduledAt,
            takenAt: takenAt,
            status: status,
            plannedDose: plannedDose,
            actualDose: actualDose,
            doseSequence: doseSequence,
            timezone: timezone,
            notes: notes,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicalCase {
    var domainModel: MedicalCase {
        MedicalCase(
            id: id,
            memberID: member,
            recordType: recordType,
            status: status,
            title: title,
            hospitalName: hospitalName,
            ageAtVisit: ageAtVisit,
            severity: severity,
            caseStatus: caseStatus,
            diagnosisSummary: diagnosisSummary,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteHealthExamReport {
    var domainModel: HealthExamReport {
        HealthExamReport(
            id: id,
            memberID: member,
            institutionName: institutionName,
            reportNo: reportNo,
            examDate: examDate,
            examType: examType,
            summary: summary,
            source: source,
            rawOCR: rawOcr,
            status: status,
            extra: extra,
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteExaminationReport {
    var domainModel: ExaminationReport {
        ExaminationReport(
            id: id,
            memberID: member,
            medicalRecordID: medicalRecord,
            category: category,
            subCategory: subCategory,
            itemName: itemName,
            performedAt: performedAt,
            reportedAt: reportedAt,
            organizationName: organizationName,
            departmentName: departmentName,
            doctorName: doctorName,
            findings: findings,
            impression: impression,
            source: source,
            rawOCR: rawOcr,
            status: status,
            extra: extra,
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteSymptom {
    var domainModel: Symptom {
        Symptom(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            name: name,
            code: code,
            severity: severity,
            startedAt: startedAt,
            durationValue: durationValue,
            durationUnit: durationUnit,
            bodyPart: bodyPart,
            notes: notes,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteVisit {
    var domainModel: Visit {
        Visit(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            visitType: visitType,
            visitedAt: visitedAt,
            department: department,
            doctorName: doctorName,
            visitNo: visitNo,
            sourceSystemID: sourceSystemId,
            notes: notes,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteSurgery {
    var domainModel: Surgery {
        Surgery(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            procedureName: procedureName,
            procedureCode: procedureCode,
            site: site,
            performedAt: performedAt,
            surgeon: surgeon,
            anesthesiaType: anesthesiaType,
            incisionLevel: incisionLevel,
            asaClass: asaClass,
            sourceSystemID: sourceSystemId,
            notes: notes,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteFollowUp {
    var domainModel: FollowUp {
        FollowUp(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            plannedAt: plannedAt,
            completedAt: completedAt,
            status: status,
            method: method,
            outcome: outcome,
            nextAction: nextAction,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedExamDetail {
    var domainModel: MedExamDetail {
        MedExamDetail(
            id: id,
            businessType: businessType,
            businessID: businessId,
            memberID: member,
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
            extra: extra,
            sortOrder: sortOrder,
            updatedAt: updatedAt
        )
    }
}
