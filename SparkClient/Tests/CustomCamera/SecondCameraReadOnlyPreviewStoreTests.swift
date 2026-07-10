#if canImport(XCTest)
import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class SecondCameraReadOnlyPreviewStoreTests: XCTestCase {
    func testFiltersNonImageInputsAndSelectsByID() async {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let inputs = [
            makeInput(id: idA, utType: UTType.jpeg.identifier),
            makeInput(id: idB, utType: UTType.pdf.identifier),
            makeInput(id: idC, utType: UTType.png.identifier),
        ]

        let store = SecondCameraReadOnlyPreviewStore(
            inputs: inputs,
            selectedID: idC,
            loader: FakePreviewImageLoader()
        )

        XCTAssertEqual(store.items.map(\.id), [idA, idC])
        XCTAssertEqual(store.selectedID, idC)
    }

    func testMissingSelectedIDFallsBackToFirst() {
        let idA = UUID()
        let idC = UUID()
        let store = SecondCameraReadOnlyPreviewStore(
            inputs: [
                makeInput(id: idA, utType: UTType.jpeg.identifier),
                makeInput(id: idC, utType: UTType.png.identifier),
            ],
            selectedID: UUID(),
            loader: FakePreviewImageLoader()
        )
        XCTAssertEqual(store.selectedID, idA)
    }

    func testEmptyInputsProduceEmptySelection() {
        let store = SecondCameraReadOnlyPreviewStore(
            inputs: [makeInput(id: UUID(), utType: UTType.pdf.identifier)],
            selectedID: UUID(),
            loader: FakePreviewImageLoader()
        )
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.selectedID)
    }

    func testChatRouteKeepsTappedIdentityAfterFiltering() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let inputs = [
            makeInput(id: idA, utType: UTType.jpeg.identifier),
            makeInput(id: idB, utType: UTType.pdf.identifier),
            makeInput(id: idC, utType: UTType.png.identifier),
        ]

        let route = ChatAttachmentPreviewRequestFactory.makeRoute(inputs: inputs, tappedID: idC)
        guard case .images(let request) = route else {
            return XCTFail("Expected images route")
        }
        XCTAssertEqual(request.inputs.map(\.id), [idA, idC])
        XCTAssertEqual(request.selectedID, idC)
    }

    func testPDFRoutesToQuickLook() {
        let idA = UUID()
        let idB = UUID()
        let inputs = [
            makeInput(id: idA, utType: UTType.jpeg.identifier),
            makeInput(id: idB, utType: UTType.pdf.identifier),
        ]
        let route = ChatAttachmentPreviewRequestFactory.makeRoute(inputs: inputs, tappedID: idB)
        guard case .quickLook(let request) = route else {
            return XCTFail("Expected quickLook route")
        }
        XCTAssertEqual(request.startIndex, 1)
        XCTAssertEqual(request.inputs.count, 2)
    }

    func testDisplayItemIdentityChangesWithRevision() {
        var item = SecondCameraReadOnlyPreviewItem(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/a.jpg"),
            displayName: "a.jpg",
            inferredUTType: .jpeg
        )
        let first = item.displayItem.imageIdentity
        item.revision += 1
        let second = item.displayItem.imageIdentity
        XCTAssertNotEqual(first, second)
    }

    private func makeInput(id: UUID, utType: String) -> FilePreviewInput {
        FilePreviewInput(
            id: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id.uuidString)"),
            displayName: id.uuidString,
            mimeType: nil,
            utTypeIdentifier: utType
        )
    }
}

private final class FakePreviewImageLoader: SecondCameraPreviewImageLoading {
    func loadPreviewImage(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        UIImage()
    }

    func loadThumbnail(from url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        UIImage()
    }
}
#endif
