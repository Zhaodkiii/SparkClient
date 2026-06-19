import SwiftUI

struct MemberLifestyleSetupSheetView: View {
    let onCompletedAction: MainActorAsyncVoidAction

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 16) {
                Text("日常健康模块第一期预留")
                    .font(.headline)
                Text("运动、睡眠、饮水、照护提醒后续再接入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("完成") {
                    Task { await onCompletedAction.call() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("日常健康")
        }
    }
}
