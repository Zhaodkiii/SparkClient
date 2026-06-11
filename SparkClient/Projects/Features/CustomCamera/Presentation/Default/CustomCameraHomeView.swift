/// 首页默认相机入口，使用默认拍摄界面与预览流程。

import SwiftUI
import AVFoundation

struct CustomCameraHomeView: View {
    let onDismiss: () -> Void
    var configuration: CustomCameraSceneConfiguration = .homeDefault
    var resultHandler: CustomCameraResultHandler = .init()

    var body: some View {
        CustomCameraScene(
            configuration: configuration,
            resultHandler: resultHandler,
            onDismiss: onDismiss
        )
        .ignoresSafeArea()
    }
}
