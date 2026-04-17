import Foundation

struct ManagedFileRecord: Codable, Sendable, Equatable {
    let id: Int
    let fileUUID: String
    let filePath: String?
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMd5: String?
    let isPublic: Bool
    let businessType: String
    let businessID: String
    let createdAt: String
    let objectKey: String?
    let storageType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fileUUID = "file_uuid"
        case filePath = "file_path"
        case originalName = "original_name"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case fileMd5 = "file_md5"
        case isPublic = "is_public"
        case businessType = "business_type"
        case businessID = "business_id"
        case createdAt = "created_at"
        case objectKey = "object_key"
        case storageType = "storage_type"
    }
}

struct ManagedFileUploadPayload: Sendable {
    let data: Data
    let fileName: String
    let businessType: String
    let businessID: String
    let isPublic: Bool
    /// 上传进度 0.0 ... 1.0；在 OSS `putObject` 阶段回调（`OSSClientWrapper` 已在主线程派发）。
    let onUploadProgress: (@Sendable (Double) -> Void)?

    init(
        data: Data,
        fileName: String,
        businessType: String,
        businessID: String = "",
        isPublic: Bool = false,
        onUploadProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        self.data = data
        self.fileName = fileName
        self.businessType = businessType
        self.businessID = businessID
        self.isPublic = isPublic
        self.onUploadProgress = onUploadProgress
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

struct FileRegistrationRequest: Codable, Sendable {
    let fileUUID: String
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMd5: String
    let isPublic: Bool
    let businessType: String
    let businessID: String
    /// 预拼接后的存储路径，登记到服务端 `file_path` 字段。
    let filePath: String
    let objectKey: String
    let storageType: String

    enum CodingKeys: String, CodingKey {
        case fileUUID = "file_uuid"
        case originalName = "original_name"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case fileMd5 = "file_md5"
        case isPublic = "is_public"
        case businessType = "business_type"
        case businessID = "business_id"
        case filePath = "file_path"
        case objectKey = "object_key"
        case storageType = "storage_type"
    }
}
