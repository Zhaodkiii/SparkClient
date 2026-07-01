#if canImport(XCTest)
import Foundation
@testable import SparkClient
import XCTest

final class ExaminationReportsListTimelineTests: XCTestCase {
    func testMakeSectionsSortsByTimeAndMergesConsecutiveSameCategories() {
        let reports = [
            makeReport(id: 1, category: "laboratory", reportedAt: date(300)),
            makeReport(id: 2, category: "laboratory", reportedAt: date(200)),
            makeReport(id: 3, category: "imaging", reportedAt: date(200)),
            makeReport(id: 4, category: "laboratory", reportedAt: date(100)),
            makeReport(id: 5, category: "laboratory", performedAt: date(150)),
            makeReport(id: 6, category: "pathology"),
        ]

        let sections = ExaminationReportTimelineSection.makeSections(from: reports)

        XCTAssertEqual(sections.map(\.category), [.laboratory, .imaging, .laboratory, .pathology])
        XCTAssertEqual(sections.map { $0.reports.map(\.id) }, [[1, 2], [3], [5, 4], [6]])
    }

    func testMakeSectionsKeepsSameDateReportsInInputOrder() {
        let reports = [
            makeReport(id: 10, category: "laboratory", reportedAt: date(200)),
            makeReport(id: 11, category: "imaging", reportedAt: date(200)),
            makeReport(id: 12, category: "laboratory", reportedAt: date(200)),
        ]

        let sections = ExaminationReportTimelineSection.makeSections(from: reports)

        XCTAssertEqual(sections.map(\.category), [.laboratory, .imaging, .laboratory])
        XCTAssertEqual(sections.map { $0.reports.map(\.id) }, [[10], [11], [12]])
    }

    private func makeReport(
        id: Int,
        category: String,
        reportedAt: Date? = nil,
        performedAt: Date? = nil
    ) -> SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments {
        SparkMedicalSyncAPI.RemoteExaminationReportWithAttachments(
            id: id,
            member: 1,
            medicalRecord: 1,
            category: category,
            subCategory: nil,
            itemName: "Report \(id)",
            performedAt: performedAt,
            reportedAt: reportedAt,
            organizationName: "Test Hospital",
            departmentName: nil,
            doctorName: nil,
            findings: nil,
            impression: nil,
            source: 1,
            status: 1,
            extra: nil,
            createdAt: date(1_000),
            updatedAt: date(1_000),
            attachments: [],
            medExamDetails: []
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
#endif
