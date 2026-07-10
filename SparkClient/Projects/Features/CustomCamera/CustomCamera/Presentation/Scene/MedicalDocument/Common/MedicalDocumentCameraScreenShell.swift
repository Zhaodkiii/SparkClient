import SwiftUI
import UIKit

/// 底部面板注入上下文：公共 Screen 只约定高度与拍摄动作，不感知缩略图数据结构。
struct MedicalDocumentCameraBottomPanelContext {
    let panelHeight: CGFloat
    let accentColor: Color
    let title: String
    let titleIcon: String
    let canFinish: Bool
    let canCapture: Bool
    let isCapturing: Bool
    let onCapture: () -> Void
    let onFinish: () -> Void

    var actionMetrics: MedicalDocumentBottomActionMetrics {
        MedicalDocumentBottomActionMetrics(panelHeight: panelHeight)
    }
}

/// 医疗文档公共相机页面骨架；通过 ViewBuilder 注入底部业务组件。
struct MedicalDocumentCameraScreenShell<BottomContent: View>: CustomCameraScreen {
    @ObservedObject var cameraManager: CustomCameraManager
    let namespace: Namespace.ID
    let closeCustomCameraAction: () -> Void

    let configuration: MedicalDocumentCameraConfiguration
    let prompt: String
    let canFinish: Bool
    let canCapture: Bool
    let onCancel: () -> Void
    let onShowGuide: () -> Void
    let onFinish: () -> Void
    let onCaptureBlocked: (() -> Void)?
    @ViewBuilder let bottomContent: (MedicalDocumentCameraBottomPanelContext) -> BottomContent

    @State private var isCapturing = false

    var body: some View {
        GeometryReader { proxy in
            let layout = MedicalDocumentCameraLayout(
                contentSize: proxy.size,
                profile: configuration.layoutProfile
            )

            ZStack {
                createCameraOutputView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                MedicalDocumentCameraOutsideMask(
                    cutoutRect: layout.viewfinderRect,
                    cornerRadius: layout.maskCornerRadius
                )
                .fill(
                    Color.black.opacity(MedicalDocumentCameraShapes.maskOpacity),
                    style: FillStyle(eoFill: true)
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                MedicalDocumentCameraViewfinderShape(
                    cornerRadiusFactor: configuration.layoutProfile.maskCornerRadiusFactor,
                    segmentFactor: configuration.layoutProfile.viewfinderSegmentFactor
                )
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: configuration.layoutProfile.viewfinderLineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(
                    width: layout.viewfinderRect.width,
                    height: layout.viewfinderRect.height
                )
                .cameraCaptureViewfinder()
                .position(
                    x: layout.viewfinderRect.midX,
                    y: layout.viewfinderRect.midY
                )

                promptText
                    .position(x: proxy.size.width / 2, y: layout.promptY)

                bottomContent(
                    MedicalDocumentCameraBottomPanelContext(
                        panelHeight: layout.bottomPanelHeight,
                        accentColor: configuration.accentColor,
                        title: configuration.navigationTitle,
                        titleIcon: configuration.context.bottomPanelIcon,
                        canFinish: canFinish,
                        canCapture: canCapture,
                        isCapturing: isCapturing,
                        onCapture: capturePhoto,
                        onFinish: onFinish
                    )
                )
                .frame(width: proxy.size.width, height: layout.bottomPanelHeight, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .bindCameraCaptureViewfinder(to: cameraManager)
        }
        .navigationTitle(configuration.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(.title2, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(width: 44, height: 44)
                }
            }

            ToolbarItem(placement: .principal) {
                Text(configuration.navigationTitle)
                    .font(.system(.largeTitle, design: .default).weight(.heavy))
                    .foregroundColor(Color(uiColor: .label))
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(.title3, design: .default).weight(.medium))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(width: 44, height: 44)
                }
            }
        }
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .statusBarHidden(false)
    }

    private var promptText: some View {
        Text(prompt)
            .font(.system(.headline, design: .default).weight(.bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 32)
            .animation(.easeInOut(duration: 0.2), value: prompt)
    }

    private func capturePhoto() {
        guard !isCapturing else { return }
        guard canCapture else {
            onCaptureBlocked?()
            return
        }

        isCapturing = true
        setOutputType(.photo)
        captureOutput()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            try? await Task.sleep(nanoseconds: MedicalDocumentBottomActionMetrics.captureCooldownNanoseconds)
            isCapturing = false
        }
    }
}
