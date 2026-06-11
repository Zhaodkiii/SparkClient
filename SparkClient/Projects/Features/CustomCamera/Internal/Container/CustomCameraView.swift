//
//  CustomCameraView.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import Combine
import SwiftUI

/**
 A view that displays a camera with state-specific screens.

 By default, it includes three screens that change depending on the status of the camera; **Error Screen**, **Camera Screen** and **Captured Media Screen**.

 Handles issues related to asking for permissions, and if permissions are not granted, it displays the **Error Screen**.

 Optionally shows the **Captured Media Screen**, which is displayed after the user captures an image or video.


 # Customization
 All of the CustomCameraView's default settings can be changed during initialisation.
 - important: To start a camera session, simply call the ``startSession()`` method. For more details, see the **Usage** section.

 ## Camera Screens
 Use one of the methods below to change the default screens:
    - ``setCameraScreen(_:)``
    - ``setCapturedMediaScreen(_:)``
    - ``setErrorScreen(_:)``

 - tip: To disable displaying captured media, call the ``setCapturedMediaScreen(_:)`` method with a nil value.

 ## Actions after capturing media
 Use one of the methods below to set actions that will be called after capturing media:
    - ``onImageCaptured(_:)``
    - ``onVideoCaptured(_:)``
 - note: If there is no **Captured Media Screen**, the action is called immediately after the media is captured, otherwise it is triggered after the user accepts the captured media in the **Captured Media Screen**.

 ## Camera Configuration
 To change the initial camera settings, use the following methods:
    - ``setCameraOutputType(_:)``
    - ``setCameraPosition(_:)``
    - ``setAudioAvailability(_:)``
    - ``setZoomFactor(_:)``
    - ``setFlashMode(_:)``
    - ``setLightMode(_:)``
    - ``setResolution(_:)``
    - ``setFrameRate(_:)``
    - ``setCameraExposureDuration(_:)``
    - ``setCameraTargetBias(_:)``
    - ``setCameraISO(_:)``
    - ``setCameraExposureMode(_:)``
    - ``setCameraHDRMode(_:)``
    - ``setCameraFilters(_:)``
    - ``setMirrorOutput(_:)``
    - ``setGridVisibility(_:)``
    - ``setFocusImage(_:)``
    - ``setFocusImageColor(_:)``
    - ``setFocusImageSize(_:)``
 - important: Note that if you try to set a value that exceeds the camera's capabilities, the camera will automatically set the closest possible value and show you which value has been set.

 ## Other
 There are other methods that you can use to customize your experience:
    - ``setCloseCustomCameraAction(_:)``
    - ``lockCameraInPortraitOrientation(_:)``

 # Usage
 ```swift
 struct ContentView: View {
    var body: some View {
        CustomCameraView()
            .setCameraFilters([.init(name: "CISepiaTone")!])
            .setCameraPosition(.back)
            .setCameraOutputType(.video)
            .setAudioAvailability(false)
            .setResolution(.hd4K3840x2160)
            .setFrameRate(30)
            .setZoomFactor(1.2)
            .setCameraISO(3)
            .setCameraTargetBias(1.2)
            .setLightMode(.on)
            .setFlashMode(.auto)

            // MUST BE CALLED!
            .startSession()
    }
 }
 ```
 */
internal struct CustomCameraView: View {
    @ObservedObject var manager: CustomCameraManager
    @Namespace var namespace
    var config: Config = .init()

    
    internal var body: some View { if config.isCameraConfigured {
        ZStack(content: createContent)
            .onDisappear(perform: onDisappear)
            .onChange(of: manager.attributes.capturedMedia, perform: onCapturedMediaChange)
    }}
}
private extension CustomCameraView {
    @ViewBuilder func createContent() -> some View {
        if let error = manager.attributes.error { createErrorScreen(error) }
        else if let capturedMedia = manager.attributes.capturedMedia, config.capturedMediaScreen != nil { createCapturedMediaScreen(capturedMedia) }
        else { createCameraScreen() }
    }
}
private extension CustomCameraView {
    func createErrorScreen(_ error: CustomCameraError) -> some View {
        config.errorScreen(error, config.closeCustomCameraAction).erased()
    }
    func createCapturedMediaScreen(_ media: CustomCameraMedia) -> some View {
        config.capturedMediaScreen?(media, namespace, onCapturedMediaRejected, onCapturedMediaAccepted)
            .erased()
            .onAppear(perform: onCaptureMediaScreenAppear)
    }
    func createCameraScreen() -> some View {
        config.cameraScreen(manager, namespace, config.closeCustomCameraAction)
            .erased()
            .onAppear(perform: onCameraAppear)
            .onDisappear(perform: onCameraDisappear)
    }
}


// MARK: - ACTIONS



// MARK: CustomCameraView
private extension CustomCameraView {
    func onDisappear() {
        lockScreenOrientation(nil)
        manager.cancel()
    }
    func onCapturedMediaChange(_ capturedMedia: CustomCameraMedia?) {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraView: 已采集媒体变更 hasMedia=\(capturedMedia != nil) usesPreview=\(config.capturedMediaScreen != nil)"
        )

        guard let capturedMedia, config.capturedMediaScreen == nil else { return }
        notifyUserOfMediaCaptured(capturedMedia)
    }
}
private extension CustomCameraView {
    func lockScreenOrientation(_ orientation: UIInterfaceOrientationMask?) {
        config.appDelegate?.orientationLock = orientation ?? .all
        UINavigationController.attemptRotationToDeviceOrientation()
    }
    func notifyUserOfMediaCaptured(_ capturedMedia: CustomCameraMedia) {
        if let image = capturedMedia.getImage() {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraView: 通知图片已采集 size=\(Int(image.size.width))x\(Int(image.size.height))"
            )
            config.imageCapturedAction(image, .init(customCameraView: self))
        }
        else if let video = capturedMedia.getVideo() {
            SparkLogger.log(
                level: .info,
                module: .camera,
                message: "CustomCameraView: 通知视频已采集 url=\(video.lastPathComponent)"
            )
            config.videoCapturedAction(video, .init(customCameraView: self))
        }
        else {
            SparkLogger.log(
                level: .warning,
                module: .camera,
                message: "CustomCameraView: 已采集媒体既无图片也无视频"
            )
        }
    }
}

// MARK: Camera Screen
private extension CustomCameraView {
    func onCameraAppear() { Task {
        do {
            try await manager.setup()
            lockScreenOrientation(.portrait)
        } catch { print("(MijickCamera) ERROR DURING SETUP: \(error)") }
    }}
    func onCameraDisappear() {
        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "CustomCameraView: 相机界面已消失，保持会话运行直至根视图消失"
        )
    }
}

// MARK: Captured Media Screen
private extension CustomCameraView {
    func onCaptureMediaScreenAppear() {
        lockScreenOrientation(nil)
    }
    func onCapturedMediaRejected() {
        manager.setCapturedMedia(nil)
    }
    func onCapturedMediaAccepted() {
        guard let capturedMedia = manager.attributes.capturedMedia else { return }
        notifyUserOfMediaCaptured(capturedMedia)
    }
}
