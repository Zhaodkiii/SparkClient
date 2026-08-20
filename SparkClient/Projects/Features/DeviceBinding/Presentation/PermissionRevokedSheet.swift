import SwiftUI
import UIKit

/// 权限收回/未授权时的温馨提示弹窗，引导用户到系统设置开启健康权限。
struct PermissionRevokedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("device.permission.guide_title", fallback: "温馨提示"))
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(L10n.format(
                "device.permission.revoked_message",
                fallback: "无法获取数据，你的%@可能暂无数据产生或系统权限未开启。\n请前往【设置-隐私与安全-健康-讯飞晓医】进行操作。",
                sourceName
            ))
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Label(
                L10n.text("device.permission.guide_path", fallback: "设置 → 隐私与安全性 → 健康 → 讯飞晓医"),
                systemImage: "gearshape.2"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                openAppSettings()
            } label: {
                Text(L10n.text("device.permission.go_settings", fallback: "去设置"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismiss()
            } label: {
                Text(L10n.text("device.permission.got_it", fallback: "知道了"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }
}