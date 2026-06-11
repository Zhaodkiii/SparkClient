/// 自定义相机临时文件存储，预留后续上传前处理与清理能力。

import Foundation

enum CustomCameraFileStore {
    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("custom-camera", isDirectory: true)
    }

    static func ensureTemporaryDirectory() throws {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }
}
