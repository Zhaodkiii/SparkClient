//
//  CustomCameraManager+NotificationCenter.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import AVFoundation
import Combine
import Foundation

@MainActor class CustomCameraManagerNotificationCenter {
    private(set) var parent: CustomCameraManager!
}

// MARK: Setup
extension CustomCameraManagerNotificationCenter {
    func setup(parent: CustomCameraManager) {
        self.parent = parent
        NotificationCenter.default.addObserver(self, selector: #selector(handleSessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: parent.captureSession)
    }
}
private extension CustomCameraManagerNotificationCenter {
    @objc func handleSessionWasInterrupted() {
        parent.attributes.lightMode = .off
        parent.videoOutput.reset()
    }
}

// MARK: Reset
extension CustomCameraManagerNotificationCenter {
    func reset() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: parent?.captureSession)
    }
}
