import SwiftUI

/// 首页「相机」模块入口。
struct HomeCustomCameraEntrySection: View {
    let onOpenCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("相机", systemImage: "camera.fill")
                    .font(.headline)
                Spacer()
            }

            Button(action: onOpenCamera) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundStyle(Color(uiColor: .systemBlue))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .systemBlue).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("拍摄照片或视频")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("打开相机")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
