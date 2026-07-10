import SwiftUI

/// 医疗文档公共相机场景配置。
struct MedicalDocumentCameraConfiguration {
    let context: MedicalDocumentCameraContext
    /// 报告类最大拍摄张数；药盒忽略该值。
    let maxCaptureCount: Int

    init(context: MedicalDocumentCameraContext, maxCaptureCount: Int = 1) {
        self.context = context
        self.maxCaptureCount = max(1, maxCaptureCount)
    }

    var layoutProfile: MedicalDocumentCameraLayoutProfile {
        context.layoutProfile
    }

    var navigationTitle: String {
        context.navigationTitle
    }

    var accentColor: Color {
        context.accentColor
    }

    var logContext: String {
        context.logContext
    }
}
