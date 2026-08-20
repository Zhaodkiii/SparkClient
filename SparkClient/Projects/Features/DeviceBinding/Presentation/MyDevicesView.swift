import SwiftUI

/// 我的设备页面：已绑定设备列表、切换绑定、删除绑定、添加入口。
struct MyDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DeviceBindingUseCase

    @State private var switchTarget: DeviceBinding?
    @State private var unbindTarget: DeviceBinding?
    @State private var guideTarget: DeviceBinding?

    init(memberContextStore: MemberContextStore) {
        _viewModel = StateObject(wrappedValue: DeviceBindingUseCase(memberContextStore: memberContextStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.bindings.isEmpty {
                    emptyState
                } else {
                    accountDataSection
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.text("device.my.title", fallback: "我的设备"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                AddDeviceView(viewModel: viewModel)
            } label: {
                Text(L10n.text("device.my.add_button", fallback: "+ 添加设备"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#2563EB"))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .task {
            await viewModel.loadBindings()
        }
        .sheet(item: $switchTarget) { binding in
            MemberSelectionSheet(
                title: L10n.text("device.switch.title", fallback: "切换绑定成员"),
                members: viewModel.members,
                selectedMemberID: binding.memberId
            ) { member in
                switchTarget = nil
                Task {
                    do {
                        try await viewModel.switchBinding(binding, to: member)
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.text("device.unbind.title", fallback: "解绑设备"),
            isPresented: Binding(
                get: { unbindTarget != nil },
                set: { if !$0 { unbindTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.text("device.unbind.confirm", fallback: "解绑"), role: .destructive) {
                if let binding = unbindTarget {
                    Task {
                        try? await viewModel.unbind(binding)
                    }
                }
                unbindTarget = nil
            }
            Button(L10n.text("device.unbind.cancel", fallback: "再想想"), role: .cancel) {
                unbindTarget = nil
            }
        } message: {
            Text(L10n.text("device.unbind.message", fallback: "是否确认解绑当前设备？"))
        }
        .sheet(item: $guideTarget) { binding in
            PermissionRevokedSheet(sourceName: binding.sourceType.displayName)
        }
        .alert(
            L10n.text("common.operation_failed", fallback: "操作失败"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok", fallback: "确定"), role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var accountDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("device.my.account_section", fallback: "账号数据"))
                    .font(.headline)
                Text(L10n.text("device.my.account_hint", fallback: "一个成员只能绑定一个健康账号"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(viewModel.bindings) { binding in
                DeviceBindingCard(
                    binding: binding,
                    onSwitch: { switchTarget = binding },
                    onDelete: { unbindTarget = binding },
                    onGuide: { guideTarget = binding }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wave.3.forward.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(L10n.text("device.my.no_data_hint", fallback: "点击下方按钮添加健康数据来源"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

/// 设备绑定卡片。
private struct DeviceBindingCard: View {
    let binding: DeviceBinding
    let onSwitch: () -> Void
    let onDelete: () -> Void
    let onGuide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                DeviceSourceIconView(sourceType: binding.sourceType, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(binding.sourceType.displayName)
                        .font(.headline)
                    if binding.authorizationStatus.isAbnormal {
                        Button(action: onGuide) {
                            Text(L10n.text("device.my.status.data_abnormal", fallback: "数据异常"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(Color.red.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            if let account = binding.accountDisplayText, !account.isEmpty {
                HStack {
                    Text(account)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 6)
            }

            Divider()
                .padding(.vertical, 12)

            HStack(spacing: 12) {
                MemberAvatarView(name: binding.memberName, avatarUrl: binding.memberAvatarUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.memberName)
                        .font(.subheadline.weight(.semibold))
                    Text(MemberRelationshipCatalog.displayTitle(for: binding.memberRelationship))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onSwitch) {
                    Text(L10n.text("device.my.switch_binding", fallback: "切换绑定"))
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

/// 数据源图标。
struct DeviceSourceIconView: View {
    let sourceType: HealthDataSourceType
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color(hex: sourceType.iconBackgroundHex))
            .frame(width: size, height: size)
            .overlay {
                if sourceType.usesAppleLogo {
                    Image(systemName: "apple.logo")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: sourceSymbol)
                        .font(.system(size: size * 0.44))
                        .foregroundStyle(.white)
                }
            }
    }

    private var sourceSymbol: String {
        switch sourceType {
        case .huaweiHealth: return "heart.circle.fill"
        case .vivoHealth: return "heart.circle.fill"
        case .coros: return "figure.run.circle.fill"
        case .bloodPressureMonitor: return "gauge.medium"
        case .glucometer: return "drop.fill"
        default: return "heart.circle.fill"
        }
    }
}

extension Color {
    /// 十六进制颜色字符串转 `Color`。
    init(hex: String) {
        var cleaned = hex
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        let parsed = UInt64(cleaned, radix: 16) ?? 0
        let r = Double((parsed >> 16) & 0xFF) / 255.0
        let g = Double((parsed >> 8) & 0xFF) / 255.0
        let b = Double(parsed & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}