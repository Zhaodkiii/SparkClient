import Foundation
// import AliyunOSSiOS // 导入阿里云 OSS SDK

/// OSSClientWrapper 是对阿里云 OSS SDK 的封装类
/// 目的：将原生的回调/任务模式转换为 Swift 现代并发模型 (async/await)
final class OSSClientWrapper {
    /// 负责管理 OSS 客户端生命周期、初始化和凭证刷新的管理类
    private let manager: OSSManager

    init(manager: OSSManager) {
        self.manager = manager
    }

    // MARK: - 上传操作

    /// 上传二进制数据到 OSS
    /// - Parameters:
    ///   - data: 要上传的 Data 对象
    ///   - objectKey: 存储在云端的文件路径（例如 "uploads/user123/avatar.png"）
    ///   - contentType: 文件 MIME 类型（例如 "image/png"）
    ///   - progressCallback: 进度回调，返回 0.0 ~ 1.0 的 Double
    func putObject(
        data: Data,
        objectKey: String,
        contentType: String,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws {
        // 1. 确保管理类已初始化（例如已获取 STS 临时凭证）
        try await manager.ensureInitialized()
        guard let client = manager.client else {
            throw OSSError.clientNotInitialized
        }

        // 2. 构建上传请求
        let request = OSSPutObjectRequest()
        request.bucketName = OSSConfiguration.bucket // 存储桶名称
        request.objectKey = objectKey               // 对象路径
        request.uploadingData = data               // 二进制数据
        request.contentType = contentType           // 内容类型
        
        // 3. 设置上传进度闭包
        request.uploadProgress = { _, sent, total in
            // 计算进度比例
            let progress = total > 0 ? Double(sent) / Double(total) : 0
            // 切换到主线程调用回调，方便 UI 更新
            Task { @MainActor in progressCallback?(progress) }
        }

        // 4. 执行异步任务
        do {
            // 使用辅助方法将 OSSTask 转换为 await
            _ = try await taskResult(client.putObject(request))
        } catch {
            throw OSSError.uploadFailed(error.localizedDescription)
        }
    }

    // MARK: - 下载操作

    /// 从 OSS 下载数据并直接返回 Data 对象
    /// - Note: 适合下载小文件（如配置文件、短文本）
    func getObject(
        objectKey: String,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws -> Data {
        try await manager.ensureInitialized()
        guard let client = manager.client else {
            throw OSSError.clientNotInitialized
        }

        let request = OSSGetObjectRequest()
        request.bucketName = OSSConfiguration.bucket
        request.objectKey = objectKey
        
        // 设置下载进度
        request.downloadProgress = { _, written, total in
            let progress = total > 0 ? Double(written) / Double(total) : 0
            Task { @MainActor in progressCallback?(progress) }
        }

        do {
            let result = try await taskResult(client.getObject(request))
            // 确保下载的数据不为空
            guard let data = result.downloadedData else {
                throw OSSError.downloadFailed("downloaded data is nil")
            }
            return data
        } catch {
            throw OSSError.downloadFailed(error.localizedDescription)
        }
    }

    /// 从 OSS 下载文件并保存到本地指定 URL
    /// - Note: 适合下载大文件（如视频、大图），避免占用过多内存
    func downloadToFile(
        objectKey: String,
        fileURL: URL,
        progressCallback: ((Double) -> Void)? = nil
    ) async throws {
        try await manager.ensureInitialized()
        guard let client = manager.client else {
            throw OSSError.clientNotInitialized
        }

        let request = OSSGetObjectRequest()
        request.bucketName = OSSConfiguration.bucket
        request.objectKey = objectKey
        request.downloadToFileURL = fileURL // 设置本地存储路径，SDK 会自动写入磁盘
        
        request.downloadProgress = { _, written, total in
            let progress = total > 0 ? Double(written) / Double(total) : 0
            Task { @MainActor in progressCallback?(progress) }
        }

        do {
            _ = try await taskResult(client.getObject(request))
        } catch {
            throw OSSError.downloadFailed(error.localizedDescription)
        }
    }

    // MARK: - 签名链接

    /// 生成一个带有时效性的预签名 URL
    /// - Parameters:
    ///   - objectKey: 对象路径
    ///   - expires: 有效时长（单位：秒），默认 1 小时
    /// - Returns: 可直接用于浏览器或第三方组件访问的 URL
    func presignedURL(
        objectKey: String,
        expires: TimeInterval = 3600
    ) async throws -> URL {
        try await manager.ensureInitialized()
        guard let client = manager.client else {
            throw OSSError.clientNotInitialized
        }
        
        // 获取签名任务
        let task = client.presignConstrainURL(
            withBucketName: OSSConfiguration.bucket,
            withObjectKey: objectKey,
            withExpirationInterval: expires
        )
        
        let result = try await taskResult(task)
        // 签名结果通常以字符串形式返回 URL
        guard let urlString = result as? String, let url = URL(string: urlString) else {
            throw OSSError.invalidResponse
        }
        return url
    }

    // MARK: - 核心转换逻辑

    /// 核心转换器：将阿里云 SDK 旧款的 `OSSTask` 转换为 Swift 的 `async throws`
    /// - Parameter task: OSS SDK 产生的异步任务对象
    /// - Returns: 任务执行成功后的结果对象
    private func taskResult<T: AnyObject>(_ task: OSSTask<T>) async throws -> T {
        // 使用 CheckedContinuation 将基于回调的代码桥接到异步环境
        try await withCheckedThrowingContinuation { continuation in
            // 调用 SDK 的 continueWith 块（这里使用了 `continue` 关键字，在 Swift 中需加反引号）
            task.`continue`(successBlock: { task in
                if let error = task.error {
                    // 任务报错，恢复异步函数并抛出异常
                    continuation.resume(throwing: error)
                } else if let result = task.result {
                    // 任务成功，返回结果
                    continuation.resume(returning: result)
                } else {
                    // 既无错误也无结果，视为非法响应
                    continuation.resume(throwing: OSSError.invalidResponse)
                }
                return nil
            })
        }
    }
}
