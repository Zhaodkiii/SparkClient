import SwiftUI

/// 编辑页工具栏删除 + 二次确认（对齐 HealthClient `TimelineClinicalEditShell` 思路）。
struct MedicalTimelineDeleteShell<Content: View>: View {
    let resourceKind: SparkMedicalResourceKind
    let resourceID: Int
    let workflowAPI: SparkMedicalWorkflowAPI
    let onDeleted: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    var body: some View {
        content()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Group {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel(L10n.text("common.delete"))
                }
            }
            .alert(
                L10n.text("home.medical.timeline.delete.confirm_title"),
                isPresented: $showDeleteConfirm
            ) {
                Button(L10n.text("common.cancel"), role: .cancel) {}
                Button(L10n.text("common.delete"), role: .destructive) {
                    Task { await performDelete() }
                }
            } message: {
                Text(L10n.text("home.medical.timeline.delete.confirm_message"))
            }
    }

    private func performDelete() async {
        await MainActor.run { isDeleting = true }
        do {
            try await workflowAPI.delete(kind: resourceKind, id: resourceID)
            await MainActor.run {
                isDeleting = false
                onDeleted()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isDeleting = false
            }
        }
    }
}

#Preview("Delete shell — Light") {
    CompatibleNavigationContainer {
        MedicalTimelineDeleteShell(
            resourceKind: .symptoms,
            resourceID: 1,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            onDeleted: {}
        ) {
            Text("Content")
                .navigationTitle("Preview")
        }
    }
    .preferredColorScheme(.light)
}

#Preview("Delete shell — Dark") {
    CompatibleNavigationContainer {
        MedicalTimelineDeleteShell(
            resourceKind: .visits,
            resourceID: 1,
            workflowAPI: AppContainer.preview.backend.medicalWorkflow,
            onDeleted: {}
        ) {
            Text("Content")
                .navigationTitle("Preview")
        }
    }
    .preferredColorScheme(.dark)
}
