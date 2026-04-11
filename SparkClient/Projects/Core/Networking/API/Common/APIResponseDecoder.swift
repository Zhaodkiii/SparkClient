import Foundation

/// 后端统一包裹结构的解码帮助器。
/// 让 Domain API 只关心业务数据，统一在这里处理 `code/msg/data` 语义。
enum APIResponseDecoder {
    static func decodeWrappedData<T: Decodable>(
        _ type: T.Type,
        from response: SparkNetworkResponse,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let wrapped = try decoder.decode(BackendWrappedResponse<T>.self, from: response.data)

        guard wrapped.code == 0 else {
            throw SparkNetworkError.httpError(
                statusCode: response.httpResponse.statusCode,
                backend: BackendError(code: wrapped.code, msg: wrapped.msg, data: nil),
                rawBody: response.data
            )
        }

        return wrapped.data
    }

    /// 与 `decodeWrappedData` 相同，但若根 JSON **没有** `code` 键（例如 Django REST 直接返回业务对象），则把整段 body 按 `T` 解码。
    /// 用于同时兼容 Spark 统一包裹与裸 JSON 响应。
    static func decodeWrappedDataOrDirect<T: Decodable>(
        _ type: T.Type,
        from response: SparkNetworkResponse,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let root = try JSONSerialization.jsonObject(with: response.data, options: [.fragmentsAllowed])
        if let dict = root as? [String: Any], dict["code"] != nil {
            return try decodeWrappedData(type, from: response, decoder: decoder)
        }
        return try decoder.decode(T.self, from: response.data)
    }
}
