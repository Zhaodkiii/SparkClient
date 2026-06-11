//
//  Typealiases.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI

internal typealias CameraScreenBuilder = @MainActor (CustomCameraManager, Namespace.ID, _ closeCustomCameraAction: @escaping () -> ()) -> any CustomCameraScreen
internal typealias CapturedMediaScreenBuilder = @MainActor (CustomCameraMedia, Namespace.ID, _ retakeAction: @escaping () -> (), _ acceptMediaAction: @escaping () -> ()) -> any CustomCapturedMediaScreen
internal typealias ErrorScreenBuilder = @MainActor (CustomCameraError, _ closeCustomCameraAction: @escaping () -> ()) -> any CustomCameraErrorScreen
