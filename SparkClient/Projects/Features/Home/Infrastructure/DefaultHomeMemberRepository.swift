import Foundation

final class DefaultHomeMemberRepository: HomeMemberRepository, @unchecked Sendable {
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let memberAPI: SparkMedicalMemberAPI
    private let logger: Logger

    init(
        medicalQueryAPI: SparkMedicalQueryAPI,
        memberAPI: SparkMedicalMemberAPI,
        logger: Logger = ConsoleLogger()
    ) {
        self.medicalQueryAPI = medicalQueryAPI
        self.memberAPI = memberAPI
        self.logger = logger
    }

    func refreshRemoteSnapshot() async throws {
        _ = try await medicalQueryAPI.listMembers()
    }

    func loadMembers() async -> [Member] {
        do {
            let members = try await medicalQueryAPI.listMembers()
            return members.map(\.domainModel)
        } catch {
            logger.error("加载成员列表失败：\(error.localizedDescription)", category: "home")
            return []
        }
    }

    func loadSnapshot(memberID: Int) async -> MedicalDataSnapshot {
        do {
            async let summary = medicalQueryAPI.fetchMemberSummary(memberID: memberID)
            async let medExamDetails = medicalQueryAPI.listMedExamDetails(memberID: memberID)
            let loadedSummary = try await summary

            return MedicalDataSnapshot(
                members: [loadedSummary.member.domainModel],
                medicalCases: loadedSummary.medicalCases.map(\.domainModel),
                symptoms: [],
                visits: [],
                surgeries: [],
                followUps: [],
                healthExamReports: loadedSummary.healthExamReports.map(\.domainModel),
                examinationReports: loadedSummary.examinationReports.map(\.domainModel),
                medExamDetails: try await medExamDetails.map(\.domainModel),
                medicalReports: [],
                prescriptionBatches: [],
                medications: loadedSummary.medications.map(\.domainModel),
                medicationTakenRecords: loadedSummary.medicationTakenRecords.map(\.domainModel),
                healthMetrics: [],
                updatedAt: Date()
            )
        } catch {
            logger.error("按成员加载医疗数据失败：memberID=\(memberID), error=\(error.localizedDescription)", category: "home")
            return .empty
        }
    }

    func createMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: "",
            allergies: [],
            chronicConditions: [],
            notes: "",
            avatarUrl: "",
            isPrimary: false
        )

        do {
            _ = try await memberAPI.createMember(payload)
            return
        } catch {
            logger.error("远端新增成员失败：\(error.localizedDescription)", category: "home")
            throw error
        }
    }

    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async throws {
        let payload = SparkMedicalMemberAPI.UpsertMemberPayload(
            name: name,
            relationship: relationship,
            gender: gender,
            birthDate: birthDate,
            bloodType: member.bloodType,
            allergies: member.allergies,
            chronicConditions: member.chronicConditions,
            notes: member.notes,
            avatarUrl: member.avatarUrl,
            isPrimary: member.isPrimary
        )

        do {
            _ = try await memberAPI.updateMember(remoteID: member.id, payload: payload)
            return
        } catch {
            logger.error("远端更新成员失败：\(error.localizedDescription)", category: "home")
            throw error
        }
    }

    func deleteMember(_ member: Member) async throws {
        do {
            try await memberAPI.deleteMember(remoteID: member.id)
            return
        } catch {
            logger.error("远端删除成员失败：\(error.localizedDescription)", category: "home")
            throw error
        }
    }
}

private extension SparkMedicalSyncAPI.RemoteMember {
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

private extension SparkMedicalSyncAPI.RemoteMedicalCase {
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

private extension SparkMedicalSyncAPI.RemoteHealthExamReport {
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

private extension SparkMedicalSyncAPI.RemoteExaminationReport {
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

private extension SparkMedicalSyncAPI.RemoteMedExamDetail {
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
            resultValue: resultValue,
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

private extension SparkMedicalSyncAPI.RemoteMedication {
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

private extension SparkMedicalSyncAPI.RemoteMedicationTakenRecord {
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
