import CryptoKit
import Foundation

struct SparkFileAPI {
    let configuration: SparkBackendConfiguration

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    init(engine: SparkNetworkEngine) {
        self.configuration = SparkBackendConfiguration(
            engine: engine,
            deviceCache: engine.cache(),
            logger: engine.networkLogger
        )
    }

    func upload(
        data: Data,
        fileName: String,
        businessType: String,
        businessID: String,
        isPublic: Bool,
        mimeType: String
    ) async throws -> ManagedFileRecord {
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let body = MultipartFormDataBuilder.build(
            boundary: MultipartFormDataBuilder.defaultBoundary,
            fields: [
                "business_type": businessType,
                "business_id": businessID,
                "is_public": isPublic ? "1" : "0",
                "file_md5": md5,
            ],
            fileFieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            fileData: data
        )

        let operation = CacheableSparkNetworkOperation(
            name: "File.Upload",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/files/upload/",
                headers: ["Content-Type": "multipart/form-data; boundary=\(MultipartFormDataBuilder.defaultBoundary)"],
                body: .raw(body, contentType: "multipart/form-data; boundary=\(MultipartFormDataBuilder.defaultBoundary)"),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "file.upload",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(ManagedFileRecord.self, from: response)
    }

    func list(
        businessType: String? = nil,
        businessID: String? = nil,
        isPublic: Bool? = nil
    ) async throws -> [ManagedFileRecord] {
        var queryItems: [URLQueryItem] = []
        if let businessType, !businessType.isEmpty {
            queryItems.append(URLQueryItem(name: "business_type", value: businessType))
        }
        if let businessID, !businessID.isEmpty {
            queryItems.append(URLQueryItem(name: "business_id", value: businessID))
        }
        if let isPublic {
            queryItems.append(URLQueryItem(name: "is_public", value: isPublic ? "1" : "0"))
        }

        let operation = CacheableSparkNetworkOperation(
            name: "File.List",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/files/",
                queryItems: queryItems,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: true,
                    serialKey: "file.list",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .normal,
                    etagTTL: 120
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData([ManagedFileRecord].self, from: response)
    }

    func updateBusinessBinding(_ item: ManagedFileBusinessUpdateItem) async throws -> ManagedFileRecord {
        let operation = CacheableSparkNetworkOperation(
            name: "File.UpdateBinding",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .patch,
                path: "/api/v1/files/business/update/",
                body: .json(AnyEncodable(item)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "file.binding.update",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .normal
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(ManagedFileRecord.self, from: response)
    }

    func downloadData(fileID: Int) async throws -> Data {
        let operation = CacheableSparkNetworkOperation(
            name: "File.Download",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/files/\(fileID)/download/",
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "file.download.\(fileID)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        guard (200...299).contains(response.httpResponse.statusCode) else {
            throw SparkNetworkError.httpError(statusCode: response.httpResponse.statusCode, backend: nil, rawBody: response.data)
        }
        return response.data
    }
}

enum MultipartFormDataBuilder {
    static let defaultBoundary = "SparkBoundary-\(UUID().uuidString)"

    static func build(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.append("\(value)\(lineBreak)")
        }

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\(lineBreak)")
        body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}
