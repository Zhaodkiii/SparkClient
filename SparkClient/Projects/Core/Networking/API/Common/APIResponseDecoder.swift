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
}
