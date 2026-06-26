import Foundation

/// Redacts inline image payloads from AI gateway request logs.
enum AIRuntimeRequestLogRedactor {
    static func redact(_ text: String) -> String {
        redactDataImageBase64(in: redactSparkInlineJPEG(in: text))
    }

    private static func redactDataImageBase64(in text: String) -> String {
        // "data:image" covers both unescaped (data:image/jpeg) and JSON-escaped (data:image\/jpeg) variants.
        let imageMarker = "data:image"
        let base64Suffix = ";base64,"
        // Maximum distance between "data:image" and ";base64," to avoid false positives (e.g. "data:image\/jpeg" is ~15 chars).
        let maxMIMELength = 30

        var result = ""
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let markerRange = text.range(of: imageMarker, range: searchStart..<text.endIndex)
        {
            let lookAheadEnd = text.index(
                markerRange.upperBound,
                offsetBy: maxMIMELength,
                limitedBy: text.endIndex
            ) ?? text.endIndex

            guard let base64Range = text.range(
                of: base64Suffix,
                range: markerRange.upperBound..<lookAheadEnd
            ) else {
                result += text[searchStart...markerRange.lowerBound]
                searchStart = text.index(after: markerRange.lowerBound)
                continue
            }

            result += text[searchStart..<markerRange.lowerBound]

            let payloadStart = base64Range.upperBound
            guard let payloadEnd = findJSONStringTerminator(in: text, startingAt: payloadStart) else {
                result += text[markerRange.lowerBound..<payloadStart]
                searchStart = payloadStart
                continue
            }
            // Keep the MIME prefix (data:image\/jpeg;base64,) and replace only the base64 payload.
            result += text[markerRange.lowerBound..<base64Range.upperBound]
            result += "<image-redacted>"
            searchStart = payloadEnd
        }

        result += text[searchStart..<text.endIndex]
        return result
    }

    private static func redactSparkInlineJPEG(in text: String) -> String {
        let marker = AIRuntimeContentPart.sparkInlineJPEGBase64Prefix
        var result = ""
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let markerRange = text.range(of: marker, range: searchStart..<text.endIndex)
        {
            result += text[searchStart..<markerRange.lowerBound]
            let payloadStart = markerRange.upperBound
            guard let payloadEnd = findJSONStringTerminator(in: text, startingAt: payloadStart) else {
                result += marker
                searchStart = text.index(after: markerRange.lowerBound)
                continue
            }
            result += "\(marker)<image-redacted>"
            searchStart = payloadEnd
        }

        result += text[searchStart..<text.endIndex]
        return result
    }

    private static func findJSONStringTerminator(in text: String, startingAt start: String.Index) -> String.Index? {
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if character == "\"" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }
}
