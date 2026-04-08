import Foundation

/// 医疗统一资源 CRUD：`/api/v1/medical/resources/?kind=<kind>` 与 `.../resources/<id>/?kind=<kind>`。
///
/// 与按实体拆分的 REST 路径行为一致，读请求启用 ETag；写请求高优先级串行键。
struct SparkMedicalResourceAPI {
    let configuration: SparkBackendConfiguration

    private static let collectionPath = "/api/v1/medical/resources/"

    init(configuration: SparkBackendConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Generic CRUD

    /// 列表 `GET .../resources/?kind=...`
    func list<T: Decodable>(
        _ type: [T].Type,
        kind: SparkMedicalResourceKind,
        query: [URLQueryItem] = []
    ) async throws -> [T] {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .get,
            path: Self.collectionPath,
            queryItems: q,
            body: nil,
            responseType: [T].self,
            allowETag: true,
            serialKey: "medical.resource.list.\(kind.rawValue)",
            queuePriority: .normal,
            isIdempotent: true
        )
    }

    /// 详情 `GET .../resources/<id>/?kind=...`
    func retrieve<T: Decodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .get,
            path: itemPath(id: id),
            queryItems: q,
            body: nil,
            responseType: T.self,
            allowETag: true,
            serialKey: "medical.resource.retrieve.\(kind.rawValue).\(id)",
            queuePriority: .normal,
            isIdempotent: true
        )
    }

    /// 新建 `POST .../resources/?kind=...`
    func create<T: Decodable, B: Encodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .post,
            path: Self.collectionPath,
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.create.\(kind.rawValue)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 部分更新 `PATCH .../resources/<id>/?kind=...`
    func update<T: Decodable, B: Encodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .patch,
            path: itemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.update.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 全量更新 `PUT .../resources/<id>/?kind=...`
    func replace<T: Decodable, B: Encodable>(
        _ type: T.Type,
        kind: SparkMedicalResourceKind,
        id: Int,
        body: B,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let q = kindQueryItems(kind, extra: query)
        return try await request(
            method: .put,
            path: itemPath(id: id),
            queryItems: q,
            body: .json(AnyEncodable(body)),
            responseType: T.self,
            allowETag: false,
            serialKey: "medical.resource.replace.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
    }

    /// 删除 `DELETE .../resources/<id>/?kind=...`
    func delete(kind: SparkMedicalResourceKind, id: Int, query: [URLQueryItem] = []) async throws {
        let q = kindQueryItems(kind, extra: query)
        let response = try await executeRaw(
            method: .delete,
            path: itemPath(id: id),
            queryItems: q,
            body: nil,
            allowETag: false,
            serialKey: "medical.resource.delete.\(kind.rawValue).\(id)",
            queuePriority: .high,
            isIdempotent: false
        )
        _ = try APIResponseDecoder.decodeWrappedData(JSONValue?.self, from: response, decoder: .sparkMedicalResource)
    }

    // MARK: - Private

    private func itemPath(id: Int) -> String {
        "\(Self.collectionPath)\(id)/"
    }

    private func kindQueryItems(_ kind: SparkMedicalResourceKind, extra: [URLQueryItem]) -> [URLQueryItem] {
        [URLQueryItem(name: "kind", value: kind.rawValue)] + extra
    }

    private func executeRaw(
        method: SparkHTTPMethod,
        path: String,
        queryItems: [URLQueryItem],
        body: SparkBody?,
        allowETag: Bool,
        serialKey: String,
        queuePriority: RequestQueuePriority,
        isIdempotent: Bool
    ) async throws -> SparkNetworkResponse {
        let operation = CacheableSparkNetworkOperation(
            name: "Medical.Resource.\(method.rawValue).\(path)",
            apiName: "SparkMedicalResourceAPI",
            request: SparkNetworkRequest(
                method: method,
                path: path,
                queryItems: queryItems,
                body: body ?? .none,
                strategy: NetworkStrategy(
                    requiresAuth: true,
                    allowETag: allowETag,
                    serialKey: serialKey,
                    retryConfig: .default,
                    isIdempotent: isIdempotent,
                    queuePriority: queuePriority,
                    etagTTL: allowETag ? 120 : nil
                )
            )
        )
        return try await configuration.execute(operation)
    }

    private func request<T: Decodable>(
        method: SparkHTTPMethod,
        path: String,
        queryItems: [URLQueryItem],
        body: SparkBody?,
        responseType: T.Type,
        allowETag: Bool,
        serialKey: String,
        queuePriority: RequestQueuePriority,
        isIdempotent: Bool
    ) async throws -> T {
        let response = try await executeRaw(
            method: method,
            path: path,
            queryItems: queryItems,
            body: body,
            allowETag: allowETag,
            serialKey: serialKey,
            queuePriority: queuePriority,
            isIdempotent: isIdempotent
        )
        return try APIResponseDecoder.decodeWrappedData(responseType, from: response, decoder: .sparkMedicalResource)
    }
}

private extension JSONDecoder {
    static let sparkMedicalResource: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(MedicalDateCoding.decodeFlexibleDate(from:))
        return decoder
    }()
}
