import CoreImage.CIFilterBuiltins
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 二维码展示（参考 travel `QRCodeView`）：白底、无插值缩放、宽度约 60% 且带上限。
struct QRCodeShareView: View {
    let payload: String
    var showsScanAction: Bool = true
    var onScanOthers: (() -> Void)?

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    private let maxSide: CGFloat = 260

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                let side = min(geometry.size.width * 0.6, maxSide)
                Group {
                    if let image = qrImage(from: payload) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .frame(width: side, height: side)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: maxSide + 24)

            Text(L10n.text("home.members.share.qr.hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if showsScanAction, let onScanOthers {
                Button(action: onScanOthers) {
                    Text(L10n.text("home.members.add.scan"))
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private func qrImage(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scale = maxSide / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
