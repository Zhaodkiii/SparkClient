import SwiftUI

struct TaskEmptyStateView: View {
    let onCreate: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("task.empty.title", comment: "今天还没有任务"))
                .font(.headline)

            Text(NSLocalizedString("task.empty.subtitle", comment: "可以创建新任务，或者先同步服务端数据"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onCreate) {
                Text(NSLocalizedString("task.empty.create", comment: "新建任务"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onRefresh) {
                Text(NSLocalizedString("task.empty.refresh", comment: "重新同步"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }
}

struct TaskLoadingSkeletonView: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(height: 88)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 200, height: 10)
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 80, height: 10)
                        }
                        .padding(16)
                    }
            }
        }
        .padding(.horizontal, 16)
        .redacted(reason: .placeholder)
    }
}
