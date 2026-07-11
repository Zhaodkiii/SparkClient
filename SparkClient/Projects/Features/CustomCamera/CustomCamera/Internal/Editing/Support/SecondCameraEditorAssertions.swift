//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

nonisolated public struct SecondCameraEditorAssertionError: Error, Sendable {
#if TESTABLE_BUILD
    public static var test_skipAssertions = false
#endif

    public let description: String
    public init(
        _ description: String,
        logger: SecondCameraEditorPrefixedLogger = .empty(),
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) {
#if TESTABLE_BUILD
        if Self.test_skipAssertions {
            logger.warn("assertionError: \(description)")
        } else {
            secondCameraEditorFailDebug("assertionError: \(description)", logger: logger, file: file, function: function, line: line)
        }
#else
        secondCameraEditorFailDebug("assertionError: \(description)", logger: logger, file: file, function: function, line: line)
#endif
        self.description = description
    }
}

// An error that won't assert.
nonisolated public struct SecondCameraEditorGenericError: Error, Sendable {
    public let description: String
    public init(_ description: String) {
        self.description = description
    }
}
