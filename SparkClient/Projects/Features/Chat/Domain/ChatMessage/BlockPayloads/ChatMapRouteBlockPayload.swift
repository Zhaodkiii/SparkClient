import Foundation

struct ChatMapLocationPayload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct ChatRoutePayload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let summary: String
    let distance: String?
    let duration: String?
    let mode: String?

    init(
        id: UUID = UUID(),
        summary: String,
        distance: String? = nil,
        duration: String? = nil,
        mode: String? = nil
    ) {
        self.id = id
        self.summary = summary
        self.distance = distance
        self.duration = duration
        self.mode = mode
    }
}

nonisolated struct ChatMapRouteBlockPayload: Codable, Equatable, Sendable {
    let locations: [ChatMapLocationPayload]
    let routes: [ChatRoutePayload]
}
