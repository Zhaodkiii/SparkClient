import AVFoundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum NutritionBarcodeScannerPhase: Equatable {
    case idle
    case checkingPermission
    case permissionDenied
    case running
    case detected(String)
    case failed(String)
}

@MainActor
final class NutritionBarcodeScannerController: NSObject, ObservableObject {
    @Published private(set) var phase: NutritionBarcodeScannerPhase = .idle
    @Published var isScanLineAnimating = false

    let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var hasConfiguredSession = false

    var onBarcodeDetected: ((String) -> Void)?

    func onAppear() {
        phase = .checkingPermission
        Task { await checkCameraPermission() }
    }

    func onDisappear() {
        stopSession()
        deactivateScanLine()
    }

    func restartScanning() {
        guard phase != .permissionDenied else { return }
        phase = .running
        startSession()
        activateScanLine()
    }

    private func checkCameraPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configureAndStart()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await configureAndStart()
            } else {
                phase = .permissionDenied
            }
        case .denied, .restricted:
            phase = .permissionDenied
        @unknown default:
            phase = .permissionDenied
        }
    }

    private func configureAndStart() async {
        guard hasConfiguredSession == false else {
            phase = .running
            startSession()
            activateScanLine()
            return
        }
        do {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
            else {
                phase = .failed(L10n.text("nutrition.barcode.failed"))
                return
            }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.metadataObjectTypes = [.ean13, .ean8, .upce, .code128, .code39, .code93]
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            }
            session.commitConfiguration()
            hasConfiguredSession = true
            phase = .running
            startSession()
            activateScanLine()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startSession() {
        guard session.isRunning == false else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func activateScanLine() {
        withAnimation(.easeInOut(duration: 0.85).delay(0.1).repeatForever(autoreverses: true)) {
            isScanLineAnimating = true
        }
    }

    func deactivateScanLine() {
        withAnimation(.easeInOut(duration: 0.85)) {
            isScanLineAnimating = false
        }
    }

    private func handleScanned(_ raw: String) {
        stopSession()
        deactivateScanLine()
        phase = .detected(raw)
        onBarcodeDetected?(raw)
    }
}

extension NutritionBarcodeScannerController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard metadataObjects.count == 1,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        Task { @MainActor in
            guard case .running = phase else { return }
            handleScanned(value)
        }
    }
}

struct NutritionBarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var controller = NutritionBarcodeScannerController()

    let onBarcodeScanned: (String) -> Void

    var body: some View {
        ZStack {
            content
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            controller.onBarcodeDetected = { barcode in
                onBarcodeScanned(barcode)
            }
            controller.onAppear()
        }
        .onDisappear {
            controller.onDisappear()
        }
        .alert(
            L10n.text("nutrition.barcode.permission_denied"),
            isPresented: permissionAlertBinding
        ) {
            Button(L10n.text("nutrition.barcode.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                dismiss()
            }
        }
    }

    private var permissionAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.phase == .permissionDenied },
            set: { if $0 == false, controller.phase == .permissionDenied { dismiss() } }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle, .checkingPermission:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .permissionDenied:
            permissionDeniedView
        case .running, .detected:
            scannerLayout
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var scannerLayout: some View {
        VStack(spacing: 8) {
            HStack {
                Button(L10n.text("nutrition.barcode.hint")) {}
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                Spacer()
                Text(L10n.text("nutrition.barcode.title"))
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)

            GeometryReader { geometry in
                let square = Swift.min(geometry.size.width - 32, 300)
                ZStack {
                    QRScannerCameraView(session: controller.session, frameSize: CGSize(width: square, height: square))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .circular)
                            .trim(from: 0.61, to: 0.64)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .rotationEffect(.degrees(Double(index) * 90))
                    }

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(y: controller.isScanLineAnimating ? square - 2 : 0)
                        .opacity(controller.phase == .running ? 1 : 0)
                }
                .frame(width: square, height: square)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text(L10n.text("nutrition.barcode.scan_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 40)
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L10n.text("nutrition.barcode.permission_denied"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(L10n.text("nutrition.barcode.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button(L10n.text("common.cancel")) { dismiss() }
        }
        .padding(32)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(L10n.text("nutrition.common.retry")) {
                controller.restartScanning()
            }
            .buttonStyle(.borderedProminent)
            Button(L10n.text("common.cancel")) { dismiss() }
        }
        .padding(32)
    }
}
