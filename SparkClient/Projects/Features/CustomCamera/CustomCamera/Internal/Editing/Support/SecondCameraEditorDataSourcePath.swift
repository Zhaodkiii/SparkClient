//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SecondCameraEditorDataSourcePath: @unchecked Sendable {
    public enum Ownership {
        /// The `SecondCameraEditorDataSourcePath` owns this URL and may consume it.
        case owned

        /// The `SecondCameraEditorDataSourcePath` is borrowing a reference to this file and must not
        /// touch it.
        case borrowed
    }

    public init(fileUrl: URL, ownership: Ownership) {
        secondCameraEditorPrecondition(fileUrl.isFileURL)
        self.fileUrl = fileUrl
        self.ownership = ownership
    }

    public convenience init(filePath: String, ownership: Ownership) {
        let fileUrl = URL(fileURLWithPath: filePath)
        self.init(fileUrl: fileUrl, ownership: ownership)
    }

    public convenience init(writingTempFileData: Data, fileExtension: String) throws {
        let fileUrl = SecondCameraEditorFileSystem.temporaryFileUrl(fileExtension: fileExtension, isAvailableWhileDeviceLocked: true)
        try writingTempFileData.write(to: fileUrl, options: .completeFileProtectionUntilFirstUserAuthentication)
        self.init(fileUrl: fileUrl, ownership: .owned)
    }

    public convenience init(writingSyncMessageData: Data) throws {
        try self.init(writingTempFileData: writingSyncMessageData, fileExtension: SecondCameraEditorMimeTypeUtil.syncMessageFileExtension)
    }

    deinit {
        if ownership == .owned, !isConsumed.get() {
            do {
                try SecondCameraEditorFileSystem.deleteFileIfExists(url: fileUrl)
            } catch {
                secondCameraEditorFailDebug("SecondCameraEditorDataSourcePath could not delete file: \(fileUrl), \(error)")
            }
        }
    }

    public let fileUrl: URL
    private let ownership: Ownership
    private let isConsumed = SecondCameraEditorAtomicBool(false, lock: .init())

    private var _sourceFilename: String?
    public var sourceFilename: String? {
        get {
            return _sourceFilename
        }
        set {
            secondCameraEditorAssertDebug(!isConsumed.get())
            _sourceFilename = newValue?.secondCameraEditor_filterFilename()
        }
    }

    public func readData() throws -> Data {
        secondCameraEditorAssertDebug(!isConsumed.get())
        return try Data(contentsOf: fileUrl, options: [.mappedIfSafe])
    }

    public func readLength() throws -> UInt64 {
        secondCameraEditorAssertDebug(!isConsumed.get())
        return UInt64(try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize!)
    }

    public func consumeAndDeleteIfNecessary() throws {
        secondCameraEditorAssertDebug(isConsumed.tryToSetFlag())
        if ownership == .owned {
            try SecondCameraEditorFileSystem.deleteFileIfExists(url: fileUrl)
        }
    }

    public func imageSource() throws -> any SecondCameraEditorImageSource {
        return try SecondCameraEditorDataImageSource.forPath(self.fileUrl.path)
    }
}
