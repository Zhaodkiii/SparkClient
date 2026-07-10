//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum StringSanitizer {
    private static let maxCodePoints = 16

    public static func isExtremelyLongGraphemeCluster(_ character: Character) -> Bool {
        character.unicodeScalars.count > Self.maxCodePoints
    }

    public static func sanitize(
        _ original: String,
        shouldRemove: (Character) -> Bool = isExtremelyLongGraphemeCluster
    ) -> String {
        guard original.contains(where: shouldRemove) else {
            return original
        }

        var remaining = original[...]
        var result = ""
        result.reserveCapacity(original.utf8.count)

        while let nextBadCharIndex = remaining.firstIndex(where: shouldRemove) {
            result.append(contentsOf: remaining[..<nextBadCharIndex])
            result.append("\u{FFFD}")
            remaining = remaining[nextBadCharIndex...].dropFirst()
        }

        result.append(contentsOf: remaining)
        return result
    }
}
