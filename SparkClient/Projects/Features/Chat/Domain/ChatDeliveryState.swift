import Foundation

enum ChatDeliveryState: String, Codable, Sendable {
    case pending
    case sending
    case sent
    case failed
    case read
}
