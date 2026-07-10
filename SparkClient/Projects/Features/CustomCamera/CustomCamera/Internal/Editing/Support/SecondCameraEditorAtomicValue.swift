//
// Signal Camera - SecondCameraEditorAtomicValue shim
//

import Foundation

public final class SecondCameraEditorAtomicValue<T>: @unchecked Sendable {
    private let lock: SecondCameraEditorUnfairLock
    private nonisolated(unsafe) var value: T

    public init(_ value: T, lock: SecondCameraEditorUnfairLock) {
        self.value = value
        self.lock = lock
    }

    public func get() -> T {
        lock.withLock { value }
    }

    public func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }

    @discardableResult
    public func swap(_ newValue: T) -> T {
        lock.withLock {
            let oldValue = value
            value = newValue
            return oldValue
        }
    }

    @discardableResult
    public func map(_ block: (T) -> T) -> T {
        lock.withLock {
            let newValue = block(value)
            value = newValue
            return newValue
        }
    }

    @discardableResult
    public func update<Result>(block: (inout T) -> Result) -> Result {
        lock.withLock {
            block(&value)
        }
    }
}
