import SwiftUI

/// 与 `Launch Screen.storyboard` 一致的启动占位视图，用于系统启动页到应用内引导的无缝过渡。
struct AppLaunchScreenView: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .overlay {
                Image("0260618")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }
    }
}
