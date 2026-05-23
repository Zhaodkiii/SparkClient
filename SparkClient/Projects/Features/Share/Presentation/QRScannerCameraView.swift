import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 相机预览（参考 travel `CameraView`）。
struct QRScannerCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    let frameSize: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: frameSize))
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = CGRect(origin: .zero, size: frameSize)
        layer.videoGravity = .resizeAspectFill
        layer.masksToBounds = true
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
        layer.frame = CGRect(origin: .zero, size: frameSize)
    }
}
