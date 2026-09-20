import SwiftUI

struct HospitalSelectionSettingsSection: View {
    @StateObject private var viewModel: HospitalSelectionViewModel

    init(accountID: Int64, dependencies: HospitalCareFeatureDependencies) {
        _viewModel = StateObject(
            wrappedValue: HospitalSelectionViewModel(
                accountID: accountID,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        Section("医院服务") {
            NavigationLink {
                HospitalSelectionView(viewModel: viewModel)
            } label: {
                HStack {
                    Text("当前医院")
                    Spacer()
                    Text(viewModel.currentHospitalDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .task { await viewModel.load() }
    }
}

struct HospitalSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HospitalSelectionViewModel

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .loading:
                ProgressView("正在加载医院…")
            case .empty:
                ContentUnavailableView("暂无可用医院", systemImage: "building.2")
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message).foregroundStyle(.secondary)
                    Button("重试") { Task { await viewModel.retry() } }
                }
            case .ready:
                List(viewModel.hospitals) { hospital in
                    Button {
                        Task {
                            if await viewModel.select(hospital) {
                                dismiss()
                            }
                        }
                    } label: {
                        HospitalSelectionRow(
                            hospital: hospital,
                            isSelected: hospital.id == viewModel.selectedHospitalID,
                            isSubmitting: hospital.id == viewModel.submittingHospitalID
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.submittingHospitalID != nil)
                }
                .refreshable { await viewModel.retry() }
            }
        }
        .navigationTitle("选择医院")
        .alert("切换医院失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct HospitalSelectionRow: View {
    let hospital: HospitalSummary
    let isSelected: Bool
    let isSubmitting: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(hospital.name)
                    .foregroundStyle(.primary)
                if hospital.shortName.isEmpty == false && hospital.shortName != hospital.name {
                    Text(hospital.shortName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if hospital.introduction.isEmpty == false {
                    Text(hospital.introduction)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isSubmitting { ProgressView() }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}
