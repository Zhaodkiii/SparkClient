import AVFoundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum QRScannerPhase: Equatable {
    case idle
    case checkingPermission
    case permissionDenied
    case running
    case detected
    case resolving
    case failed(String)
}

@MainActor
final class QRScannerController: NSObject, ObservableObject {
    @Published private(set) var phase: QRScannerPhase = .idle
    @Published var isScanLineAnimating = false
    @Published var showInvalidCodeAlert = false

    let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var hasConfiguredSession = false

    var onTicketResolved: ((String) -> Void)?

    override init() {
        super.init()
    }

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

    func retryAfterFailure() {
        phase = .running
        startSession()
        activateScanLine()
    }

    func resumeAfterInvalidCodeAlert() {
        showInvalidCodeAlert = false
        restartScanning()
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
                phase = .failed(L10n.text("home.members.share.scan.failed"))
                return
            }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.metadataObjectTypes = [.qr]
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
        guard let ticket = MemberShareDeepLinkParser.ticket(fromRaw: raw) else {
            showInvalidCodeAlert = true
            return
        }
        phase = .detected
        onTicketResolved?(ticket)
    }
}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        Task { @MainActor in
            guard phase == .running else { return }
            handleScanned(value)
        }
    }
}

struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var controller: QRScannerController

    let onTicketScanned: (String) -> Void

    init(onTicketScanned: @escaping (String) -> Void) {
        _controller = StateObject(wrappedValue: QRScannerController())
        self.onTicketScanned = onTicketScanned
    }

    var body: some View {
        ZStack {
            content
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            controller.onTicketResolved = { ticket in
                onTicketScanned(ticket)
            }
            controller.onAppear()
        }
        .onDisappear {
            controller.onDisappear()
        }
        .alert(
            L10n.text("home.members.share.scan.permission_denied"),
            isPresented: permissionAlertBinding
        ) {
            Button(L10n.text("home.members.share.scan.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                dismiss()
            }
        }
        .alert(
            L10n.text("home.members.share.scan.invalid_code"),
            isPresented: $controller.showInvalidCodeAlert
        ) {
            Button(L10n.text("home.members.share.scan.retry")) {
                controller.resumeAfterInvalidCodeAlert()
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                dismiss()
            }
        } message: {
            Text(L10n.text("home.members.share.scan.invalid_code_hint"))
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
        case .running, .detected, .resolving:
            scannerLayout
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var scannerLayout: some View {
        VStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            VStack(spacing: 6) {
                Text(L10n.text("home.members.share.scan.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.text("home.members.share.scan.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            GeometryReader { geometry in
                let square = min(geometry.size.width, 300)
                ZStack {
                    QRScannerCameraView(session: controller.session, frameSize: CGSize(width: square, height: square))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .scaleEffect(0.97)

                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .circular)
                            .trim(from: 0.61, to: 0.64)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .rotationEffect(.degrees(Double(index) * 90))
                    }

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2.5)
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: controller.isScanLineAnimating ? 8 : -8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .offset(y: controller.isScanLineAnimating ? square - 2 : 0)
                        .opacity(controller.phase == .running ? 1 : 0)
                }
                .frame(width: square, height: square)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 45)

            if controller.phase == .resolving {
                ProgressView(L10n.text("home.members.share.scan.resolving"))
                    .font(.footnote)
                    .padding(.top, 8)
            }

            Spacer(minLength: 12)

            Button {
                controller.restartScanning()
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
            .disabled(controller.phase == .resolving)

            Spacer(minLength: 40)
        }
        .padding(15)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L10n.text("home.members.share.scan.permission_denied"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(L10n.text("home.members.share.scan.open_settings")) {
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
            Button(L10n.text("home.members.share.scan.retry")) {
                controller.retryAfterFailure()
            }
            .buttonStyle(.borderedProminent)
            Button(L10n.text("common.cancel")) { dismiss() }
        }
        .padding(32)
    }
}
