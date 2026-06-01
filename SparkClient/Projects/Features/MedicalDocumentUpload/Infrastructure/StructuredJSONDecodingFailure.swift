import Foundation

struct StructuredJSONDecodingFailureContext: Sendable {
    let error: Error
    let outputPreview: String
    let kindLabel: String
}

struct StructuredJSONDecodingFailure: Error {
    let context: StructuredJSONDecodingFailureContext
}
