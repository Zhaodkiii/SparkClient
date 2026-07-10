import SwiftUI

/// 报告类底部面板缩略图尺寸。
struct ReportDocumentBottomPanelMetrics {
    let panelHeight: CGFloat

    var thumbnailHeight: CGFloat { clamp(panelHeight * 0.36, min: 72, max: 92) }
    var thumbnailWidth: CGFloat { thumbnailHeight * 0.72 }
    var thumbnailCornerRadius: CGFloat { clamp(thumbnailHeight * 0.11, min: 8, max: 10) }
    var thumbnailSpacing: CGFloat { 10 }
    var deleteButtonSize: CGFloat { clamp(thumbnailHeight * 0.30, min: 22, max: 28) }
    var deleteIconSize: CGFloat { deleteButtonSize * 0.40 }
    var deleteButtonOffset: CGFloat { deleteButtonSize * 0.20 }
    var pageBadgeSize: CGFloat { clamp(thumbnailHeight * 0.28, min: 20, max: 24) }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }
}

/// 报告类连续缩略图底部拍摄组件。
struct ReportDocumentCameraBottomPanel: View {
    let context: MedicalDocumentCameraBottomPanelContext
    let emptyThumbnailIcon: String
    let capturedImages: [ReportDocumentCapturedImage]
    let onPreview: (ReportDocumentCapturedImage) -> Void
    let onDelete: (ReportDocumentCapturedImage) -> Void

    private var actionMetrics: MedicalDocumentBottomActionMetrics { context.actionMetrics }
    private var thumbnailMetrics: ReportDocumentBottomPanelMetrics {
        ReportDocumentBottomPanelMetrics(panelHeight: context.panelHeight)
    }

    var body: some View {
        VStack(spacing: actionMetrics.rowSpacing) {
            thumbnailScrollRow

            HStack(alignment: .center) {
                MedicalDocumentCameraChrome.titleLeading(
                    icon: context.titleIcon,
                    title: context.title,
                    accentColor: context.accentColor,
                    metrics: actionMetrics
                )

                Spacer(minLength: 0)

                MedicalDocumentCameraChrome.captureButton(
                    accentColor: context.accentColor,
                    metrics: actionMetrics,
                    isEnabled: context.canCapture,
                    isCapturing: context.isCapturing,
                    action: context.onCapture
                )

                Spacer(minLength: 0)

                MedicalDocumentCameraChrome.finishButton(
                    accentColor: context.accentColor,
                    metrics: actionMetrics,
                    canFinish: context.canFinish,
                    action: context.onFinish
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .padding(.top, actionMetrics.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MedicalDocumentCameraChrome.bottomPanelBackground())
    }

    private var thumbnailScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: thumbnailMetrics.thumbnailSpacing) {
                if capturedImages.isEmpty {
                    emptyThumbnailPlaceholder
                } else {
                    ForEach(capturedImages) { item in
                        thumbnailItem(for: item)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: thumbnailMetrics.thumbnailHeight + 4)
    }

    private var emptyThumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: thumbnailMetrics.thumbnailCornerRadius, style: .continuous)
            .stroke(Color(uiColor: .separator).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .frame(width: thumbnailMetrics.thumbnailWidth, height: thumbnailMetrics.thumbnailHeight)
            .overlay {
                Image(systemName: emptyThumbnailIcon)
                    .font(.system(size: thumbnailMetrics.thumbnailHeight * 0.28, weight: .medium))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
    }

    private func thumbnailItem(for item: ReportDocumentCapturedImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onPreview(item)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailMetrics.thumbnailWidth, height: thumbnailMetrics.thumbnailHeight)
                        .clipShape(
                            RoundedRectangle(cornerRadius: thumbnailMetrics.thumbnailCornerRadius, style: .continuous)
                        )

                    Text("\(item.index)")
                        .font(.system(size: thumbnailMetrics.pageBadgeSize * 0.55, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: thumbnailMetrics.pageBadgeSize, height: thumbnailMetrics.pageBadgeSize)
                        .background(Circle().fill(context.accentColor))
                        .padding(6)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: thumbnailMetrics.thumbnailCornerRadius, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            MedicalDocumentCameraChrome.deleteButton(
                size: thumbnailMetrics.deleteButtonSize,
                iconSize: thumbnailMetrics.deleteIconSize,
                offset: thumbnailMetrics.deleteButtonOffset
            ) {
                onDelete(item)
            }
        }
    }
}
