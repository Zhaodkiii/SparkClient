/// 拍摄结果回调，第一期首页入口仅用于关闭相机；后续业务可接入上传或识别。

import Foundation

struct CustomCameraResultHandler {
    var onConfirmed: (CustomCameraSceneResult) -> Void = { _ in }
    var onCancelled: () -> Void = {}
}
