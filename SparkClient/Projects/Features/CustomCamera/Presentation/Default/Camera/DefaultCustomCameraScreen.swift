//
//  DefaultCustomCameraScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

@MainActor
struct DefaultCustomCameraScreen: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    internal let namespace: Namespace.ID
    internal let closeCustomCameraAction: () -> ()
    var config: Config = .init()


    internal var body: some View {
        ZStack {
            createContentView()
            createTopBar()
            createBottomBar()
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.mijickBackgroundPrimary).ignoresSafeArea())
        .statusBarHidden()
        .animation(.mSpring)
    }
}
private extension DefaultCustomCameraScreen {
    func createTopBar() -> some View {
        DefaultCustomCameraScreen.TopBar(parent: self)
            .frame(maxHeight: .infinity, alignment: .top)
    }
    func createContentView() -> some View {
        createCameraOutputView()
            .ignoresSafeArea()
    }
    func createBottomBar() -> some View {
        DefaultCustomCameraScreen.BottomBar(parent: self)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

extension DefaultCustomCameraScreen {
    var iconAngle: Angle { switch isOrientationLocked {
        case true: deviceOrientation.getAngle()
        case false: .zero
    }}
}
