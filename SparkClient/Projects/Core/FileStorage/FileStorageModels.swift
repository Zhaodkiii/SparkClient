import Foundation

struct ManagedFileRecord: Codable, Sendable, Equatable {
    let id: Int
    let fileUuid: String
    let filePath: String?
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMd5: String?
    let isPublic: Bool
    let businessType: String
    let businessId: String
    let createdAt: String
    let objectKey: String?
    let storageType: String?
}

struct ManagedFileUploadPayload: Sendable {
    let data: Data
    let fileName: String
    let businessType: String
    let businessId: String
    let isPublic: Bool
    /// 上传进度 0.0 ... 1.0；在 OSS `putObject` 阶段回调（`OSSClientWrapper` 已在主线程派发）。
    let onUploadProgress: (@Sendable (Double) -> Void)?
}

struct ManagedFileBusinessUpdateItem: Codable, Sendable {
    let fileId: Int
    let businessType: String
    let businessId: String
}

struct FileRegistrationRequest: Codable, Sendable {
    let fileUuid: String
    let originalName: String
    let fileSize: Int
    let mimeType: String
    let fileMd5: String
    let isPublic: Bool
    let businessType: String
    let businessId: String
    /// 预拼接后的存储路径，登记到服务端 `file_path` 字段。
    let filePath: String
    let objectKey: String
    let storageType: String
}
