/// 场景化相机配置，供不同业务入口复用同一套底层能力。

import AVFoundation

struct CustomCameraSceneConfiguration {
    var outputType: CameraOutputType = .photo
    var cameraPosition: CameraPosition = .back
    var isAudioAvailable: Bool = true
    var showsCapturedMediaPreview: Bool = true
    var showsGrid: Bool = false
    var mirrorOutput: Bool = false

    static let homeDefault = CustomCameraSceneConfiguration(
        outputType: .photo,
        cameraPosition: .back,
        isAudioAvailable: true,
        showsCapturedMediaPreview: true,
        showsGrid: false,
        mirrorOutput: false
    )
}
