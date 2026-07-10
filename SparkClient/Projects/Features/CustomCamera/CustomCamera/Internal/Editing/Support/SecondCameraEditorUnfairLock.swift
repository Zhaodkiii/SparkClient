//
// Signal Camera - lock + atomics shim
//

import Foundation

public final class SecondCameraEditorUnfairLock: @unchecked Sendable {
    private let mutex = NSLock()

    public init() {}

    public func lock() {
        mutex.lock()
    }

    public func unlock() {
        mutex.unlock()
    }

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        mutex.lock()
        defer { mutex.unlock() }
        return try body()
    }
}

public extension SecondCameraEditorUnfairLock {
    static let sharedGlobal = SecondCameraEditorUnfairLock()
}

public final class SecondCameraEditorAtomicUInt: @unchecked Sendable {
    private let value: SecondCameraEditorAtomicValue<UInt>

    public init(_ value: UInt = 0, lock: SecondCameraEditorUnfairLock) {
        self.value = SecondCameraEditorAtomicValue(value, lock: lock)
    }

    public func get() -> UInt { value.get() }
    public func set(_ value: UInt) { self.value.set(value) }

    @discardableResult
    public func increment() -> UInt { value.map { $0 + 1 } }
}

public enum SecondCameraEditorAttachmentThumbnailQuality {
    case small
    case mediumLarge
    case backupThumbnail
}
