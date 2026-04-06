import SwiftUI

/// 上传页面容器：只负责三态页面编排，业务逻辑交给 ViewModel。
struct MedicalDocumentUploadHostView: View {
    @ObservedObject var viewModel: MedicalDocumentUploadViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showPreviewSheet = false
    @State private var previewIndex = 0

    var body: some View {
        // 三态主渲染：选择文件 -> 处理中 -> 结果展示。
        Group {
            switch viewModel.stage {
            case .picking:
                pickingContent
            case .processing:
                MedicalDocumentUploadProgressView(
                    steps: viewModel.progressSteps,
                    errorMessage: viewModel.errorMessage
                )
            case .result:
                if let result = viewModel.recognitionResult {
                    MedicalDocumentUploadResultView(
                        result: result,
                        isSaving: viewModel.isSaving,
                        saveReceipt: viewModel.saveReceipt,
                        onBack: { viewModel.reset() },
                        onSave: {
                            Task {
                                _ = await viewModel.saveResult()
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle("医疗文档上传")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .sheet(isPresented: $showPreviewSheet) {
            // 预览索引保护：仅在索引有效时打开统一预览组件。
            if viewModel.previewItems.indices.contains(previewIndex) {
                UnifiedFilePreview(input: viewModel.previewItems[previewIndex]) {
                    showPreviewSheet = false
                }
            }
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("好") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    /// 文件选择态：展示成员信息、选择入口、已选文件预览网格和识别入口。
    private var pickingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                memberCard
                pickerCard
                if viewModel.previewItems.isEmpty == false {
                    MedicalDocumentPreviewGrid(
                        items: viewModel.previewItems,
                        onTap: { index in
                            previewIndex = index
                            showPreviewSheet = true
                        },
                        onRemove: { id in
                            viewModel.removeFile(id: id)
                        }
                    )
                }
                Button {
                    // 识别流程由 ViewModel 统一驱动，视图层不直接调用 OCR/AI。
                    Task { await viewModel.startRecognition() }
                } label: {
                    Label("开始识别", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canStartRecognition == false)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// 当前成员卡片：上传归属直接绑定首页已选成员，不再做患者匹配。
    private var memberCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前成员")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(viewModel.selectedMemberName ?? "未选择成员")
                .font(.headline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    /// 文件选择卡片：按系统版本分流不同选择组件，保持统一交互文案与入口布局。
    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择文件")
                .font(.headline)
            Group {
                if #available(iOS 16.0, *) {
                    // iOS 16+：使用新组件（含 PhotosPicker 能力）。
                    MedicalDocumentFilePickerMenu(
                        buttonContent: {
                            Label("添加照片/相机/文件", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        },
                        onFilesSelected: { files in
                            viewModel.setSelectedFiles(viewModel.selectedFiles + files)
                        }
                    )
                } else {
                    // iOS 15：使用独立 legacy 组件（不依赖 PhotosPicker）。
                    MedicalDocumentLegacyFilePickerMenu(
                        buttonContent: {
                            Label("添加照片/相机/文件", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        },
                        onFilesSelected: { files in
                            viewModel.setSelectedFiles(viewModel.selectedFiles + files)
                        }
                    )
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }
}

#Preview {
    NavigationView {
        MedicalDocumentUploadHostView(viewModel: .preview())
    }
}
