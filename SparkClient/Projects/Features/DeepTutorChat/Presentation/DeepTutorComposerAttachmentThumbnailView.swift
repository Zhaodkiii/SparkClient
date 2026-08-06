import SwiftUI

struct DeepTutorComposerAttachmentThumbnailView: View {
    let draft: DeepTutorComposerAttachmentDraft
    let onUpload: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onPreview: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onPreview) {
                content
                    .frame(width: cardWidth, height: 68)
                    .background(DeepTutorPalette.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: draft.phase == .failed ? 1.5 : 1)
                    }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .disabled(draft.phase == .uploading)
            .opacity(draft.phase == .uploading ? 0.4 : 1)
        }
    }

    private var cardWidth: CGFloat {
        draft.isImage ? 68 : 196
    }

    private var borderColor: Color {
        switch draft.phase {
        case .failed:
            return .red.opacity(0.55)
        case .uploaded:
            return Color.accentColor.opacity(0.35)
        default:
            return DeepTutorPalette.mutedBorderColor
        }
    }

    @ViewBuilder
    private var content: some View {
        if draft.isImage {
            imageThumbnail
        } else {
            fileThumbnail
        }
    }

    private var imageThumbnail: some View {
        ZStack {
            if let image = UIImage(data: draft.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            phaseOverlay
        }
    }

    private var fileThumbnail: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: draft.kind == .pdf ? "doc.richtext.fill" : "doc.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                Text(fileExtension)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.12)))
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(draft.byteCount), countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                statusRow
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch draft.phase {
        case .localSelected:
            Button("上传", action: onUpload)
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
        case .uploading:
            HStack(spacing: 6) {
                ProgressView(value: draft.uploadProgress, total: 1)
                    .controlSize(.small)
                Text("\(Int(draft.uploadProgress * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .uploaded:
            Label("已上传", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.errorMessage ?? "上传失败")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("重试", action: onRetry)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch draft.phase {
        case .localSelected:
            VStack {
                Spacer()
                Button("上传", action: onUpload)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.18))
        case .uploading:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView(value: draft.uploadProgress, total: 1)
                    .tint(.white)
                    .padding(12)
            }
        case .uploaded:
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(6)
                }
                Spacer()
            }
        case .failed:
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("重试", action: onRetry)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
        }
    }

    private var fileExtension: String {
        let ext = (draft.displayName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
}
