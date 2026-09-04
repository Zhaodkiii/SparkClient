#if canImport(UIKit)
import SwiftUI
import UIKit

/// 医院智能体/医生统一头像视图。
///
/// - 图片加载复用项目通用文件下载缓存 `MarkdownRemoteImageCache`
///   （NSCache 内存 + Caches 磁盘，按 URL SHA256 命名），同一 URL 不重复下载；
///   头像 URL 自带版本参数，版本变化后自然命中新缓存键。
/// - 非方形照片按比例填充并锚定上半部分（`.top` 对齐裁剪），避免人脸被居中裁掉。
/// - 加载失败或无 URL 时回退占位：优先 asset 图，其次名称首字。
struct HospitalAvatarImageView: View {
    enum AvatarShape {
        case circle
        case roundedSquare(ratio: CGFloat)
    }

    let urlString: String
    let size: CGFloat
    var shape: AvatarShape = .circle
    /// 占位文案（通常取名称首字）；为空且未提供 asset 时显示 person 图标。
    var placeholderText: String = ""
    /// 可选 asset 占位图名（如首页的 avatarDoctor）。
    var placeholderAsset: String? = nil
    var accent: Color = .accentColor

    @State private var image: UIImage?
    @State private var failed = false

    private var url: URL? {
        guard urlString.isEmpty == false else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(clipShape)
            .accessibilityHidden(true)
            .task(id: urlString) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image, failed == false {
            // 顶部对齐：超出部分只裁掉下半区域，保留人脸所在的上半部分。
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size, alignment: .top)
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let placeholderAsset, placeholderAsset.isEmpty == false {
            Image(placeholderAsset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size, alignment: .top)
        } else {
            clipShape
                .fill(accent.opacity(0.14))
                .overlay {
                    if placeholderText.isEmpty == false {
                        Text(String(placeholderText.prefix(1)))
                            .font(placeholderFont)
                            .foregroundStyle(accent)
                    } else {
                        Image(systemName: "person.fill")
                            .font(placeholderFont)
                            .foregroundStyle(accent)
                    }
                }
        }
    }

    private var placeholderFont: Font {
        size >= 60 ? .title2.weight(.semibold) : .headline.weight(.semibold)
    }

    private var clipShape: AnyShape {
        switch shape {
        case .circle:
            return AnyShape(Circle())
        case .roundedSquare(let ratio):
            return AnyShape(RoundedRectangle(cornerRadius: max(6, size * ratio), style: .continuous))
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = false
            return
        }
        failed = false
        do {
            let cached = try await MarkdownRemoteImageCache.shared.image(for: url)
            image = cached.image
        } catch {
            image = nil
            failed = true
        }
    }
}
#endif
