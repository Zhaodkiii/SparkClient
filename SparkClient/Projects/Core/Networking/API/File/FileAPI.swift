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

    func registerFile(_ requestBody: FileRegistrationRequest) async throws -> ManagedFileRecord {
        let operation = CacheableSparkNetworkOperation(
            name: "File.Register",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .post,
                path: "/api/v1/files/register/",
                body: .json(AnyEncodable(requestBody)),
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "file.register",
                    retryConfig: .default,
                    isIdempotent: false,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        return try APIResponseDecoder.decodeWrappedData(ManagedFileRecord.self, from: response)
    }

    func getPresignedDownloadURL(fileID: Int, expires: TimeInterval = 3600) async throws -> URL {
        let operation = CacheableSparkNetworkOperation(
            name: "File.DownloadURL",
            apiName: "FileAPI",
            request: SparkNetworkRequest(
                method: .get,
                path: "/api/v1/files/\(fileID)/download-url/",
                queryItems: [URLQueryItem(name: "expires", value: String(Int(expires)))],
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: false,
                    serialKey: "file.download.url.\(fileID)",
                    retryConfig: .default,
                    isIdempotent: true,
                    queuePriority: .high
                )
            )
        )

        let response = try await configuration.execute(operation)
        let payload = try APIResponseDecoder.decodeWrappedData(PresignedDownloadResponse.self, from: response)
        guard let url = URL(string: payload.url) else {
            throw SparkNetworkError.decoding(
                NSError(domain: "SparkFileAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid presigned URL"])
            )
        }
        return url
    }
}

private struct PresignedDownloadResponse: Codable {
    let url: String
}
