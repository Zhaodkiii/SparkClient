import Foundation

extension SparkMedicalMemberAPI.RemoteMember {
    var domainModel: Member {
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
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMember {
    var domainModel: Member {
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
            updatedAt: updatedAt
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

extension SparkMedicalSyncAPI.RemotePrescriptionBatchComplete {
    var domainBatch: PrescriptionBatch {
        PrescriptionBatch(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            prescriberName: prescriberName ?? "",
            institutionName: institutionName ?? "",
            prescribedAt: prescribedAt,
            diagnosis: diagnosis ?? "",
            batchNo: batchNo ?? "",
            status: status ?? "",
            auditorName: auditorName ?? "",
            auditedAt: auditedAt,
            extra: extra ?? [:],
            updatedAt: updatedAt ?? Date(timeIntervalSince1970: 0)
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedication {
    var domainModel: Medication {
        Medication(
            id: id,
            memberID: member,
            batchID: batch,
            genericName: genericName,
            brandName: brandName,
            drugName: drugName,
            dosageForm: dosageForm,
            strength: strength,
            route: route,
            dosePerTime: dosePerTime,
            doseValue: doseValue,
            doseUnit: doseUnit,
            frequencyCode: frequencyCode,
            period: period,
            timesPerPeriod: timesPerPeriod,
            frequencyText: frequencyText,
            durationDays: durationDays,
            instructions: instructions,
            reminderEnabled: reminderEnabled,
            reminderTimes: reminderTimes,
            sortOrder: sortOrder,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}

extension SparkMedicalSyncAPI.RemoteMedicationTakenRecord {
    var domainModel: MedicationTakenRecord {
        MedicationTakenRecord(
            id: id,
            memberID: member,
            medicationID: medication,
            scheduledAt: scheduledAt,
            takenAt: takenAt,
            status: status,
            doseSequence: doseSequence,
            actualDose: actualDose,
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
            rawOCR: rawOCR,
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
            rawOCR: rawOCR,
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
            sourceSystemID: sourceSystemID,
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
            sourceSystemID: sourceSystemID,
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
            businessID: businessID,
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

extension SparkMedicalSyncAPI.RemotePrescriptionBatch {
    var domainModel: PrescriptionBatch {
        PrescriptionBatch(
            id: id,
            memberID: member,
            medicalCaseID: medicalCase,
            prescriberName: prescriberName,
            institutionName: institutionName,
            prescribedAt: prescribedAt,
            diagnosis: diagnosis,
            batchNo: batchNo ?? "",
            status: status,
            auditorName: auditorName,
            auditedAt: auditedAt,
            extra: extra ?? [:],
            updatedAt: updatedAt
        )
    }
}
