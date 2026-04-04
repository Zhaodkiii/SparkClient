import Foundation

struct ManagedFileRecord: Codable, Sendable, Equatable {
    let id: Int
    let fileUUID: String
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMd5: String?
    let isPublic: Bool
    let businessType: String
    let businessID: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileUUID = "file_uuid"
        case originalName = "original_name"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case fileMd5 = "file_md5"
        case isPublic = "is_public"
        case businessType = "business_type"
        case businessID = "business_id"
        case createdAt = "created_at"
    }
}

struct ManagedFileUploadPayload: Sendable {
    let data: Data
    let fileName: String
    let businessType: String
    let businessID: String
    let isPublic: Bool

    init(
        data: Data,
        fileName: String,
        businessType: String,
        businessID: String = "",
        isPublic: Bool = false
    ) {
        self.data = data
        self.fileName = fileName
        self.businessType = businessType
        self.businessID = businessID
        self.isPublic = isPublic
    }
}

struct ManagedFileBusinessUpdateItem: Codable, Sendable {
    let fileID: Int
    let businessType: String
    let businessID: String

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case businessType = "business_type"
        case businessID = "business_id"
    }
}
