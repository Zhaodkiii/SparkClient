//
//  Public+UI+CustomCapturedMediaScreen.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.




import SwiftUI
import AVFoundation

/**
 Screen that displays the captured media.

 - important: A view conforming to **CustomCapturedMediaScreen** has to be passed directly to ``CustomCameraView``. See ``CustomCameraView/setCapturedMediaScreen(_:)`` for more details.


 ## Usage
 ```swift
 struct ContentView: View {
    var body: some View {
        CustomCameraView()
            .setCapturedMediaScreen(CustomCapturedMediaScreen.init)

            // MUST BE CALLED!
            .startSession()
    }
 }

 // MARK: Custom Captured Media Screen
 struct CustomCapturedMediaScreen: CustomCapturedMediaScreen {
    let capturedMedia: CustomCameraMedia
    let namespace: Namespace.ID
    let retakeAction: () -> ()
    let acceptMediaAction: () -> ()


    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            createContentView()
            Spacer()
            createButtons()
        }
    }
 }
 private extension CustomCapturedMediaScreen {
    func createContentView() -> some View { ZStack {
        if let image = capturedMedia.getImage() { createImageView(image) }
        else { EmptyView() }
    }}
    func createButtons() -> some View {
        HStack(spacing: 24) {
            createRetakeButton()
            createSaveButton()
        }
    }
 }
 private extension CustomCapturedMediaScreen {
    func createImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .ignoresSafeArea()
    }
    func createRetakeButton() -> some View {
        Button(action: retakeAction) { Text("Retake") }
    }
    func createSaveButton() -> some View {
        Button(action: acceptMediaAction) { Text("Save") }
    }
 }
 ```
 */
internal protocol CustomCapturedMediaScreen: View {
    var capturedMedia: CustomCameraMedia { get }
    var namespace: Namespace.ID { get }
    var retakeAction: () -> () { get }
    var acceptMediaAction: () -> () { get }
}
