import SwiftUI
import UniformTypeIdentifiers

struct MedicalUploadFlowView: View {
    @ObservedObject var viewModel: MedicalUploadFlowViewModel
    @Environment(\.dismiss) private var dismiss

    private enum ImportMode {
        case image
        case document
    }

    @State private var importMode: ImportMode = .document
    @State private var pickedFileURL: URL?
    @State private var selectedFile: UploadLocalFile?
    @State private var showFileImporter = false
    @State private var showLeaveConfirm = false
    @State private var showSaveSuccess = false

    var body: some View {
        Group {
            switch viewModel.stage {
            case .picking:
                pickerContent
            case .processing:
                processingContent
            case .result:
                resultContent
            }
        }
        .navigationTitle(L10n.text("medical.upload.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    handleCloseTapped()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importMode == .image ? [.image] : [.pdf, .plainText, .rtf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let first = urls.first else { return }
            pickedFileURL = first
            selectedFile = copyIntoTemporaryFile(from: first)
        }
        .alert(L10n.text("medical.upload.leave.title"), isPresented: $showLeaveConfirm) {
            Button(L10n.text("medical.upload.leave.stay"), role: .cancel) {}
            Button(L10n.text("medical.upload.leave.leave"), role: .destructive) {
                viewModel.reset()
                dismiss()
            }
        } message: {
            Text(L10n.text("medical.upload.leave.message"))
        }
        .alert(L10n.text("medical.upload.saved.title"), isPresented: $showSaveSuccess) {
            Button(L10n.text("medical.upload.saved.done")) {
                dismiss()
            }
        } message: {
            Text(L10n.text("medical.upload.saved.message"))
        }
    }

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                memberCard
                selectionCard
                actionCard
                if let errorMessage = viewModel.errorMessage {
                    errorCard(message: errorMessage)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("medical.upload.current_member"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(viewModel.selectedMemberName ?? L10n.text("medical.upload.member.not_selected"))
                .font(.headline)
            Text(L10n.text("medical.upload.member.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("medical.upload.select_file"))
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    importMode = .image
                    showFileImporter = true
                } label: {
                    Label(L10n.text("medical.upload.pick_photo"), systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    importMode = .document
                    showFileImporter = true
                } label: {
                    Label(L10n.text("medical.upload.pick_document"), systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let selectedFile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("medical.upload.selected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedFile.displayName)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }

    private var actionCard: some View {
        Button {
            guard let selectedFile else { return }
            Task {
                await viewModel.beginRecognition(filePath: selectedFile.url.path)
            }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text(L10n.text("medical.upload.start"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedFile == nil)
    }

    private var processingContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(L10n.text("medical.upload.processing"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.progressSteps) { step in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: step.state))
                            .foregroundStyle(color(for: step.state))
                        Text(step.title)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

            if let errorMessage = viewModel.errorMessage {
                errorCard(message: errorMessage)
                Button(L10n.text("medical.upload.retry")) {
                    viewModel.reset()
                    selectedFile = nil
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var resultContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let draft = viewModel.draft {
                    groupCard(title: L10n.text("medical.upload.result.title"), value: draft.title)
                    groupCard(title: L10n.text("medical.upload.result.summary"), value: draft.summary)
                    groupCard(title: L10n.text("medical.upload.result.diagnosis"), value: draft.diagnosis ?? L10n.text("medical.upload.result.empty_diagnosis"))
                    groupCard(
                        title: L10n.text("medical.upload.result.occurred_at"),
                        value: draft.occurredAt.formatted(date: .abbreviated, time: .omitted)
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    errorCard(message: errorMessage)
                }

                HStack(spacing: 12) {
                    Button(L10n.text("medical.upload.discard")) {
                        showLeaveConfirm = true
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            let success = await viewModel.confirmDraft()
                            if success {
                                showSaveSuccess = true
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.text("medical.upload.save"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func groupCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }

    private func errorCard(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func copyIntoTemporaryFile(from source: URL) -> UploadLocalFile? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
        let fileName = "medical_upload_\(UUID().uuidString).\(ext)"
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            return UploadLocalFile(url: target, displayName: source.lastPathComponent)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            return nil
        }
    }

    private func handleCloseTapped() {
        switch viewModel.stage {
        case .result:
            showLeaveConfirm = true
        case .processing:
            showLeaveConfirm = true
        case .picking:
            viewModel.reset()
            dismiss()
        }
    }

    private func icon(for state: MedicalUploadFlowViewModel.ProgressStep.State) -> String {
        switch state {
        case .waiting:
            return "circle"
        case .running:
            return "clock.fill"
        case .done:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private func color(for state: MedicalUploadFlowViewModel.ProgressStep.State) -> Color {
        switch state {
        case .waiting:
            return .secondary
        case .running:
            return .blue
        case .done:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct UploadLocalFile: Equatable {
    let url: URL
    let displayName: String
}

#Preview {
    NavigationView {
        MedicalUploadFlowView(viewModel: .preview())
    }
}
