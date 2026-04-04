import CoreData
import Foundation

actor CoreDataMedicalSnapshotStore {
    private let coreDataStack: CoreDataStack
    private let logger: Logger
    private let logCategory = "medical.persistence"

    init(coreDataStack: CoreDataStack, logger: Logger = ConsoleLogger()) {
        self.coreDataStack = coreDataStack
        self.logger = logger
    }

    func loadSnapshot() async throws -> MedicalDataSnapshot {
        let startedAt = Date()
        logger.info("loadSnapshot 开始", category: logCategory)
        do {
            let snapshot = try await coreDataStack.performBackgroundTask { context in
                let members = try self.fetchMembers(context)
                let medicalCases = try self.fetchMedicalCases(context)
                let examinationReports = try self.fetchExaminationReports(context)
                let medicalReports = try self.fetchMedicalReports(context)
                let prescriptions = try self.fetchPrescriptions(context)

                return MedicalDataSnapshot(
                    members: members,
                    medicalCases: medicalCases,
                    examinationReports: examinationReports,
                    medicalReports: medicalReports,
                    prescriptions: prescriptions,
                    healthMetrics: [],
                    updatedAt: Date()
                )
            }
            let cost = Date().timeIntervalSince(startedAt)
            logger.info(
                "loadSnapshot 完成 cost=\(format(cost))s members=\(snapshot.members.count) medicalCases=\(snapshot.medicalCases.count) examinationReports=\(snapshot.examinationReports.count) medicalReports=\(snapshot.medicalReports.count) prescriptions=\(snapshot.prescriptions.count)",
                category: logCategory
            )
            return snapshot
        } catch {
            let cost = Date().timeIntervalSince(startedAt)
            logger.error("loadSnapshot 失败 cost=\(format(cost))s error=\(error.localizedDescription)", category: logCategory)
            throw error
        }
    }

    func saveSnapshot(_ snapshot: MedicalDataSnapshot) async throws {
        let startedAt = Date()
        logger.info(
            "saveSnapshot 开始 members=\(snapshot.members.count) medicalCases=\(snapshot.medicalCases.count) examinationReports=\(snapshot.examinationReports.count) medicalReports=\(snapshot.medicalReports.count) prescriptions=\(snapshot.prescriptions.count)",
            category: logCategory
        )
        do {
            let report = try await coreDataStack.performBackgroundTask { context in
                let memberStats = try self.syncMembers(snapshot.members, context: context)
                let caseStats = try self.syncMedicalCases(snapshot.medicalCases, context: context)
                let examStats = try self.syncExaminationReports(snapshot.examinationReports, context: context)
                let medicalReportStats = try self.syncMedicalReports(snapshot.medicalReports, context: context)
                let prescriptionStats = try self.syncPrescriptions(snapshot.prescriptions, context: context)
                return [
                    "MemberEntity": memberStats,
                    "MedicalCaseEntity": caseStats,
                    "ExaminationReportEntity": examStats,
                    "MedicalReportEntity": medicalReportStats,
                    "PrescriptionEntity": prescriptionStats
                ]
            }
            let cost = Date().timeIntervalSince(startedAt)
            logger.info("saveSnapshot 完成 cost=\(format(cost))s", category: logCategory)
            for (entity, stats) in report.sorted(by: { $0.key < $1.key }) {
                logger.info(
                    "\(entity) existing=\(stats.existing) incoming=\(stats.incoming) inserted=\(stats.inserted) updated=\(stats.updated) deleted=\(stats.deleted)",
                    category: logCategory
                )
            }
        } catch {
            let cost = Date().timeIntervalSince(startedAt)
            logger.error("saveSnapshot 失败 cost=\(format(cost))s error=\(error.localizedDescription)", category: logCategory)
            throw error
        }
    }

    // MARK: - Fetch

    private func fetchMembers(_ context: NSManagedObjectContext) throws -> [Member] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "MemberEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPrimary", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]

        return try context.fetch(request).compactMap { obj in
            guard
                let id = obj.value(forKey: "id") as? UUID,
                let name = obj.value(forKey: "name") as? String,
                let gender = obj.value(forKey: "gender") as? String,
                let relationship = obj.value(forKey: "relationship") as? String,
                let avatar = obj.value(forKey: "avatar") as? String,
                let updatedAt = obj.value(forKey: "updatedAt") as? Date
            else { return nil }

            let remoteIDRaw = obj.value(forKey: "remoteID") as? Int64 ?? -1
            let ageRaw = obj.value(forKey: "age") as? Int32 ?? 0
            let isPrimary = obj.value(forKey: "isPrimary") as? Bool ?? false
            let birthDate = obj.value(forKey: "birthDate") as? Date

            return Member(
                id: id,
                remoteID: remoteIDRaw >= 0 ? Int(remoteIDRaw) : nil,
                name: name,
                age: Int(ageRaw),
                gender: gender,
                relationship: relationship,
                avatar: avatar,
                birthDate: birthDate,
                isPrimary: isPrimary,
                updatedAt: updatedAt
            )
        }
    }

    private func fetchMedicalCases(_ context: NSManagedObjectContext) throws -> [MedicalCase] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "MedicalCaseEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "visitDate", ascending: false)]

        return try context.fetch(request).compactMap { obj in
            guard
                let id = obj.value(forKey: "id") as? UUID,
                let memberID = obj.value(forKey: "memberID") as? UUID,
                let title = obj.value(forKey: "title") as? String,
                let chiefComplaint = obj.value(forKey: "chiefComplaint") as? String,
                let diagnosis = obj.value(forKey: "diagnosis") as? String,
                let severity = obj.value(forKey: "severity") as? String,
                let visitDate = obj.value(forKey: "visitDate") as? Date,
                let status = obj.value(forKey: "status") as? String,
                let notes = obj.value(forKey: "notes") as? String,
                let updatedAt = obj.value(forKey: "updatedAt") as? Date
            else { return nil }

            let remoteIDRaw = obj.value(forKey: "remoteID") as? Int64 ?? -1

            return MedicalCase(
                id: id,
                remoteID: remoteIDRaw >= 0 ? Int(remoteIDRaw) : nil,
                memberID: memberID,
                title: title,
                chiefComplaint: chiefComplaint,
                diagnosis: diagnosis,
                severity: severity,
                visitDate: visitDate,
                status: status,
                notes: notes,
                updatedAt: updatedAt
            )
        }
    }

    private func fetchExaminationReports(_ context: NSManagedObjectContext) throws -> [ExaminationReport] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ExaminationReportEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        return try context.fetch(request).compactMap { obj in
            guard
                let id = obj.value(forKey: "id") as? UUID,
                let memberID = obj.value(forKey: "memberID") as? UUID,
                let category = obj.value(forKey: "category") as? String,
                let subcategory = obj.value(forKey: "subcategory") as? String,
                let reportName = obj.value(forKey: "reportName") as? String,
                let checkType = obj.value(forKey: "checkType") as? String,
                let conclusion = obj.value(forKey: "conclusion") as? String,
                let doctorAdvice = obj.value(forKey: "doctorAdvice") as? String,
                let date = obj.value(forKey: "date") as? Date,
                let updatedAt = obj.value(forKey: "updatedAt") as? Date
            else { return nil }

            let remoteIDRaw = obj.value(forKey: "remoteID") as? Int64 ?? -1
            let medicalCaseID = obj.value(forKey: "medicalCaseID") as? UUID

            return ExaminationReport(
                id: id,
                remoteID: remoteIDRaw >= 0 ? Int(remoteIDRaw) : nil,
                memberID: memberID,
                medicalCaseID: medicalCaseID,
                category: category,
                subcategory: subcategory,
                reportName: reportName,
                checkType: checkType,
                conclusion: conclusion,
                doctorAdvice: doctorAdvice,
                date: date,
                updatedAt: updatedAt
            )
        }
    }

    private func fetchMedicalReports(_ context: NSManagedObjectContext) throws -> [MedicalReport] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "MedicalReportEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        return try context.fetch(request).compactMap { obj in
            guard
                let id = obj.value(forKey: "id") as? UUID,
                let memberID = obj.value(forKey: "memberID") as? UUID,
                let reportType = obj.value(forKey: "reportType") as? String,
                let title = obj.value(forKey: "title") as? String,
                let hospital = obj.value(forKey: "hospital") as? String,
                let doctor = obj.value(forKey: "doctor") as? String,
                let content = obj.value(forKey: "content") as? String,
                let date = obj.value(forKey: "date") as? Date,
                let updatedAt = obj.value(forKey: "updatedAt") as? Date
            else { return nil }

            let remoteIDRaw = obj.value(forKey: "remoteID") as? Int64 ?? -1
            let medicalCaseID = obj.value(forKey: "medicalCaseID") as? UUID

            return MedicalReport(
                id: id,
                remoteID: remoteIDRaw >= 0 ? Int(remoteIDRaw) : nil,
                memberID: memberID,
                medicalCaseID: medicalCaseID,
                reportType: reportType,
                title: title,
                hospital: hospital,
                doctor: doctor,
                content: content,
                date: date,
                updatedAt: updatedAt
            )
        }
    }

    private func fetchPrescriptions(_ context: NSManagedObjectContext) throws -> [Prescription] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PrescriptionEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        return try context.fetch(request).compactMap { obj in
            guard
                let id = obj.value(forKey: "id") as? UUID,
                let memberID = obj.value(forKey: "memberID") as? UUID,
                let drugName = obj.value(forKey: "drugName") as? String,
                let dosage = obj.value(forKey: "dosage") as? String,
                let frequency = obj.value(forKey: "frequency") as? String,
                let instructions = obj.value(forKey: "instructions") as? String,
                let status = obj.value(forKey: "status") as? String,
                let updatedAt = obj.value(forKey: "updatedAt") as? Date
            else { return nil }

            let remoteIDRaw = obj.value(forKey: "remoteID") as? Int64 ?? -1
            let medicalCaseID = obj.value(forKey: "medicalCaseID") as? UUID
            let durationDays = Int(obj.value(forKey: "durationDays") as? Int32 ?? 0)
            let startDate = obj.value(forKey: "startDate") as? Date
            let endDate = obj.value(forKey: "endDate") as? Date

            return Prescription(
                id: id,
                remoteID: remoteIDRaw >= 0 ? Int(remoteIDRaw) : nil,
                memberID: memberID,
                medicalCaseID: medicalCaseID,
                drugName: drugName,
                dosage: dosage,
                frequency: frequency,
                durationDays: durationDays,
                instructions: instructions,
                startDate: startDate,
                endDate: endDate,
                status: status,
                updatedAt: updatedAt
            )
        }
    }

    // MARK: - Sync

    private func syncMembers(_ rows: [Member], context: NSManagedObjectContext) throws -> SyncStats {
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MemberEntity"))
        var byID: [UUID: NSManagedObject] = [:]
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID { byID[id] = obj }
        }
        let incoming = Set(rows.map(\.id))
        var deleted = 0
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID, incoming.contains(id) == false {
                context.delete(obj)
                deleted += 1
            }
        }
        var inserted = 0
        var updated = 0
        for row in rows {
            let object = byID[row.id]
            let obj = object ?? NSEntityDescription.insertNewObject(forEntityName: "MemberEntity", into: context)
            if object == nil { inserted += 1 } else { updated += 1 }
            obj.setValue(row.id, forKey: "id")
            obj.setValue(Int64(row.remoteID ?? -1), forKey: "remoteID")
            obj.setValue(row.name, forKey: "name")
            obj.setValue(Int32(row.age), forKey: "age")
            obj.setValue(row.gender, forKey: "gender")
            obj.setValue(row.relationship, forKey: "relationship")
            obj.setValue(row.avatar, forKey: "avatar")
            obj.setValue(row.birthDate, forKey: "birthDate")
            obj.setValue(row.isPrimary, forKey: "isPrimary")
            obj.setValue(row.updatedAt, forKey: "updatedAt")
        }
        return SyncStats(existing: existing.count, incoming: rows.count, inserted: inserted, updated: updated, deleted: deleted)
    }

    private func syncMedicalCases(_ rows: [MedicalCase], context: NSManagedObjectContext) throws -> SyncStats {
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MedicalCaseEntity"))
        var byID: [UUID: NSManagedObject] = [:]
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID { byID[id] = obj }
        }
        let incoming = Set(rows.map(\.id))
        var deleted = 0
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID, incoming.contains(id) == false {
                context.delete(obj)
                deleted += 1
            }
        }
        var inserted = 0
        var updated = 0
        for row in rows {
            let object = byID[row.id]
            let obj = object ?? NSEntityDescription.insertNewObject(forEntityName: "MedicalCaseEntity", into: context)
            if object == nil { inserted += 1 } else { updated += 1 }
            obj.setValue(row.id, forKey: "id")
            obj.setValue(Int64(row.remoteID ?? -1), forKey: "remoteID")
            obj.setValue(row.memberID, forKey: "memberID")
            obj.setValue(row.title, forKey: "title")
            obj.setValue(row.chiefComplaint, forKey: "chiefComplaint")
            obj.setValue(row.diagnosis, forKey: "diagnosis")
            obj.setValue(row.severity, forKey: "severity")
            obj.setValue(row.visitDate, forKey: "visitDate")
            obj.setValue(row.status, forKey: "status")
            obj.setValue(row.notes, forKey: "notes")
            obj.setValue(row.updatedAt, forKey: "updatedAt")
        }
        return SyncStats(existing: existing.count, incoming: rows.count, inserted: inserted, updated: updated, deleted: deleted)
    }

    private func syncExaminationReports(_ rows: [ExaminationReport], context: NSManagedObjectContext) throws -> SyncStats {
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ExaminationReportEntity"))
        var byID: [UUID: NSManagedObject] = [:]
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID { byID[id] = obj }
        }
        let incoming = Set(rows.map(\.id))
        var deleted = 0
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID, incoming.contains(id) == false {
                context.delete(obj)
                deleted += 1
            }
        }
        var inserted = 0
        var updated = 0
        for row in rows {
            let object = byID[row.id]
            let obj = object ?? NSEntityDescription.insertNewObject(forEntityName: "ExaminationReportEntity", into: context)
            if object == nil { inserted += 1 } else { updated += 1 }
            obj.setValue(row.id, forKey: "id")
            obj.setValue(Int64(row.remoteID ?? -1), forKey: "remoteID")
            obj.setValue(row.memberID, forKey: "memberID")
            obj.setValue(row.medicalCaseID, forKey: "medicalCaseID")
            obj.setValue(row.category, forKey: "category")
            obj.setValue(row.subcategory, forKey: "subcategory")
            obj.setValue(row.reportName, forKey: "reportName")
            obj.setValue(row.checkType, forKey: "checkType")
            obj.setValue(row.conclusion, forKey: "conclusion")
            obj.setValue(row.doctorAdvice, forKey: "doctorAdvice")
            obj.setValue(row.date, forKey: "date")
            obj.setValue(row.updatedAt, forKey: "updatedAt")
        }
        return SyncStats(existing: existing.count, incoming: rows.count, inserted: inserted, updated: updated, deleted: deleted)
    }

    private func syncMedicalReports(_ rows: [MedicalReport], context: NSManagedObjectContext) throws -> SyncStats {
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "MedicalReportEntity"))
        var byID: [UUID: NSManagedObject] = [:]
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID { byID[id] = obj }
        }
        let incoming = Set(rows.map(\.id))
        var deleted = 0
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID, incoming.contains(id) == false {
                context.delete(obj)
                deleted += 1
            }
        }
        var inserted = 0
        var updated = 0
        for row in rows {
            let object = byID[row.id]
            let obj = object ?? NSEntityDescription.insertNewObject(forEntityName: "MedicalReportEntity", into: context)
            if object == nil { inserted += 1 } else { updated += 1 }
            obj.setValue(row.id, forKey: "id")
            obj.setValue(Int64(row.remoteID ?? -1), forKey: "remoteID")
            obj.setValue(row.memberID, forKey: "memberID")
            obj.setValue(row.medicalCaseID, forKey: "medicalCaseID")
            obj.setValue(row.reportType, forKey: "reportType")
            obj.setValue(row.title, forKey: "title")
            obj.setValue(row.hospital, forKey: "hospital")
            obj.setValue(row.doctor, forKey: "doctor")
            obj.setValue(row.content, forKey: "content")
            obj.setValue(row.date, forKey: "date")
            obj.setValue(row.updatedAt, forKey: "updatedAt")
        }
        return SyncStats(existing: existing.count, incoming: rows.count, inserted: inserted, updated: updated, deleted: deleted)
    }

    private func syncPrescriptions(_ rows: [Prescription], context: NSManagedObjectContext) throws -> SyncStats {
        let existing = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PrescriptionEntity"))
        var byID: [UUID: NSManagedObject] = [:]
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID { byID[id] = obj }
        }
        let incoming = Set(rows.map(\.id))
        var deleted = 0
        for obj in existing {
            if let id = obj.value(forKey: "id") as? UUID, incoming.contains(id) == false {
                context.delete(obj)
                deleted += 1
            }
        }
        var inserted = 0
        var updated = 0
        for row in rows {
            let object = byID[row.id]
            let obj = object ?? NSEntityDescription.insertNewObject(forEntityName: "PrescriptionEntity", into: context)
            if object == nil { inserted += 1 } else { updated += 1 }
            obj.setValue(row.id, forKey: "id")
            obj.setValue(Int64(row.remoteID ?? -1), forKey: "remoteID")
            obj.setValue(row.memberID, forKey: "memberID")
            obj.setValue(row.medicalCaseID, forKey: "medicalCaseID")
            obj.setValue(row.drugName, forKey: "drugName")
            obj.setValue(row.dosage, forKey: "dosage")
            obj.setValue(row.frequency, forKey: "frequency")
            obj.setValue(Int32(row.durationDays), forKey: "durationDays")
            obj.setValue(row.instructions, forKey: "instructions")
            obj.setValue(row.startDate, forKey: "startDate")
            obj.setValue(row.endDate, forKey: "endDate")
            obj.setValue(row.status, forKey: "status")
            obj.setValue(row.updatedAt, forKey: "updatedAt")
        }
        return SyncStats(existing: existing.count, incoming: rows.count, inserted: inserted, updated: updated, deleted: deleted)
    }

    private func format(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private struct SyncStats {
        let existing: Int
        let incoming: Int
        let inserted: Int
        let updated: Int
        let deleted: Int
    }
}
