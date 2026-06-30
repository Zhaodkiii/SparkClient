import SwiftUI
import UIKit

// MARK: - 方形缩略图单元

/// 单格正方形：图片路径异步解码为 `UIImage` 避免阻塞主线程绘制；非图片展示文档图标 + 本地化文件名。
struct MedicalDocumentFilePreviewSquareCard: View {
    let item: FilePreviewInput
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let cardSize = geometry.size.width

            ZStack(alignment: .topTrailing) {
                Group {
                    if item.isImage {
                        LocalFileImageThumbnail(url: item.fileURL)
                            .frame(width: cardSize, height: cardSize)
                            .clipped()
                            .background(Color(uiColor: .tertiarySystemFill))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: min(cardSize * 0.3, 32)))
                                .foregroundStyle(Color.accentColor)
                            Text(item.resolvedDisplayName)
                                .font(.system(size: min(cardSize * 0.11, 11)))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: cardSize, height: cardSize)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.10),
                                    Color(.systemIndigo).opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onPreview)

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: min(cardSize * 0.24, 24)))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(
                            Circle()
                                .fill(Color(.systemRed))
                                .frame(width: min(cardSize * 0.24, 24), height: min(cardSize * 0.24, 24))
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 本地图片缩略图加载

/// 在 `.task` 中触发异步读取；使用 `Task.detached` 将 `Data(contentsOf:)` 与 `UIImage` 解码放在后台，避免滚动卡顿。
struct LocalFileImageThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()

            } else {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    ProgressView()
                }
            }
        }
        .task(id: url) {
            image = await Self.loadImage(at: url)
        }
    }

    private static func loadImage(at url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }
}
