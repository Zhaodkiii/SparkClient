import SwiftUI

/// 选择并添加设备页面：账号数据 + 医疗器械分组，当前仅苹果健康可接入。
struct AddDeviceView: View {
    @ObservedObject var viewModel: DeviceBindingUseCase

    @State private var pickMemberForAppleHealth = false
    @State private var unavailableSource: HealthDataSourceType?
    @State private var bindErrorMessage: String?

    private let accountSources: [HealthDataSourceType] = [
        .huaweiHealth, .appleHealth, .vivoHealth, .coros,
    ]
    private let medicalDevices: [HealthDataSourceType] = [
        .bloodPressureMonitor, .glucometer,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                section(
                    title: L10n.text("device.my.account_section", fallback: "账号数据"),
                    sources: accountSources
                )
                section(
                    title: L10n.text("device.medical_section", fallback: "医疗器械"),
                    sources: medicalDevices
                )
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.text("device.add.title", fallback: "选择并添加设备"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickMemberForAppleHealth) {
            MemberSelectionSheet(
                title: L10n.text("device.add.select_member", fallback: "选择绑定成员"),
                members: viewModel.members,
                selectedMemberID: appleHealthBinding?.memberId
            ) { member in
                pickMemberForAppleHealth = false
                bindAppleHealth(to: member)
            }
        }
        .alert(
            unavailableSource?.displayName ?? "",
            isPresented: Binding(
                get: { unavailableSource != nil },
                set: { if !$0 { unavailableSource = nil } }
            )
        ) {
            Button(L10n.text("common.ok", fallback: "确定"), role: .cancel) {
                unavailableSource = nil
            }
        } message: {
            Text(L10n.text("device.access.not_available", fallback: "该功能暂未接入，敬请期待"))
        }
        .alert(
            L10n.text("common.operation_failed", fallback: "操作失败"),
            isPresented: Binding(
                get: { bindErrorMessage != nil },
                set: { if !$0 { bindErrorMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok", fallback: "确定"), role: .cancel) {
                bindErrorMessage = nil
            }
        } message: {
            Text(bindErrorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("device.add.title", fallback: "选择并添加设备"))
                .font(.title2.weight(.bold))
            Text(L10n.text("device.add.subtitle", fallback: "同步设备数据，为你提供更精准的健康解读服务"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func section(title: String, sources: [HealthDataSourceType]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(sources) { source in
                SourceRow(
                    source: source,
                    isBound: isBound(source),
                    onPrimaryAction: {
                        handleTap(source)
                    }
                )
            }
        }
    }

    private var appleHealthBinding: DeviceBinding? {
        viewModel.bindings.first { $0.sourceType == .appleHealth }
    }

    private func isBound(_ source: HealthDataSourceType) -> Bool {
        viewModel.bindings.contains { $0.sourceType == source }
    }

    private func handleTap(_ source: HealthDataSourceType) {
        guard source.isAvailable else {
            unavailableSource = source
            return
        }
        if isBound(source) {
            return
        }
        pickMemberForAppleHealth = true
    }

    private func bindAppleHealth(to member: Member) {
        Task {
            do {
                try await viewModel.bindAppleHealth(to: member)
            } catch let error as DeviceBindingError {
                bindErrorMessage = error.errorDescription
            } catch {
                bindErrorMessage = error.localizedDescription
            }
        }
    }
}

/// 数据源行。
private struct SourceRow: View {
    let source: HealthDataSourceType
    let isBound: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DeviceSourceIconView(sourceType: source, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(.headline)
                Text(source.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailingButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .opacity(shouldDim ? 0.5 : 1.0)
    }

    private var shouldDim: Bool {
        !source.isAvailable
    }

    @ViewBuilder
    private var trailingButton: some View {
        if isBound {
            Text(L10n.text("device.status.authorized", fallback: "已同步"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if source.isAvailable {
            Button(action: onPrimaryAction) {
                Text(L10n.text("device.add.go_sync", fallback: "去同步"))
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: onPrimaryAction) {
                Text(buttonTitle)
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    private var buttonTitle: String {
        source.category == .medicalDevice
            ? L10n.text("device.add.go_bind", fallback: "去绑定")
            : L10n.text("device.add.go_sync", fallback: "去同步")
    }
}