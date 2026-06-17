import Foundation

/// iOS 16 回部署兼容：把 `async` 函数类型包进 class，避免 SwiftUI / Combine 反射类型字段时解析
/// `nonisolated(nonsending)` 元数据崩溃。View / ObservableObject 只持有 class 引用。
@MainActor
final class MainActorAsyncVoidAction {
    private let perform: () async -> Void

    init(perform: @escaping () async -> Void) {
        self.perform = perform
    }

    func call() async {
        await perform()
    }
}

@MainActor
final class MainActorAsyncAction<Input> {
    private let perform: (Input) async -> Void

    init(perform: @escaping (Input) async -> Void) {
        self.perform = perform
    }

    deinit {}

    func call(_ input: Input) async {
        await perform(input)
    }
}

@MainActor
final class MainActorThrowingAction<Input> {
    private let perform: (Input) async throws -> Void

    init(perform: @escaping (Input) async throws -> Void) {
        self.perform = perform
    }

    deinit {}

    func call(_ input: Input) async throws {
        try await perform(input)
    }
}

@MainActor
final class MainActorThrowingVoidAction {
    private let perform: () async throws -> Void

    init(perform: @escaping () async throws -> Void) {
        self.perform = perform
    }

    func call() async throws {
        try await perform()
    }
}

@MainActor
final class MainActorThrowingReturningAction<Input, Output> {
    private let perform: (Input) async throws -> Output

    init(perform: @escaping (Input) async throws -> Output) {
        self.perform = perform
    }

    deinit {}

    func call(_ input: Input) async throws -> Output {
        try await perform(input)
    }
}
