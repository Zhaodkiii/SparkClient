import SwiftUI

/// 药盒槽位专属尺寸；公共按钮尺寸走 `MedicalDocumentBottomActionMetrics`。
struct MedicineBoxBottomPanelMetrics {
    let panelHeight: CGFloat

    private var scale: CGFloat {
        panelHeight / 268
    }

    var slotThumbnailHeight: CGFloat { 88 * scale }
    var slotLabelSpacing: CGFloat { 6 * scale }
    var slotCornerRadius: CGFloat { 10 * scale }
    var placeholderIconSize: CGFloat { 22 * scale }
    var slotSpacing: CGFloat { 12 }
    var slotHorizontalPadding: CGFloat { 20 }
    var slotLabelHeight: CGFloat { 34 * scale }
    var slotPreviewRowHeight: CGFloat { slotThumbnailHeight + slotLabelSpacing + slotLabelHeight }
}

/// 药盒三个固定槽位底部拍摄组件。
struct MedicineBoxCameraBottomPanel: View {
    let context: MedicalDocumentCameraBottomPanelContext
    @ObservedObject var workflow: MedicineBoxCaptureWorkflow
    let onPreviewSlot: (MedicineBoxCaptureSlot) -> Void

    private var actionMetrics: MedicalDocumentBottomActionMetrics { context.actionMetrics }
    private var slotMetrics: MedicineBoxBottomPanelMetrics {
        MedicineBoxBottomPanelMetrics(panelHeight: context.panelHeight)
    }

    var body: some View {
        VStack(spacing: actionMetrics.rowSpacing) {
            slotPreviewRow

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
                    isEnabled: true,
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

    private var slotPreviewRow: some View {
        GeometryReader { proxy in
            let horizontalPadding = slotMetrics.slotHorizontalPadding
            let spacing = slotMetrics.slotSpacing
            let slotCount = CGFloat(MedicineBoxCaptureSlot.allCases.count)
            let availableWidth = max(0, proxy.size.width - horizontalPadding * 2 - spacing * (slotCount - 1))
            let itemWidth = floor(availableWidth / slotCount)

            HStack(spacing: spacing) {
                ForEach(MedicineBoxCaptureSlot.allCases) { slot in
                    slotPreviewItem(for: slot, width: itemWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .frame(height: slotMetrics.slotPreviewRowHeight)
    }

    private func slotPreviewItem(for slot: MedicineBoxCaptureSlot, width: CGFloat) -> some View {
        let isSelected = workflow.selectedSlot == slot
        let image = workflow.image(for: slot)
        let thumbnailHeight = slotMetrics.slotThumbnailHeight

        return VStack(spacing: slotMetrics.slotLabelSpacing) {
            ZStack(alignment: .topTrailing) {
                Button {
                    handleSlotTap(slot)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: slotMetrics.slotCornerRadius, style: .continuous)
                            .fill(
                                isSelected
                                    ? context.accentColor.opacity(0.12)
                                    : Color(uiColor: .secondarySystemBackground)
                            )
                            .frame(height: thumbnailHeight)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: thumbnailHeight)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: slotMetrics.slotCornerRadius, style: .continuous)
                                )
                        } else {
                            Image(systemName: slot.placeholderSystemImage)
                                .font(.system(size: slotMetrics.placeholderIconSize, weight: .semibold))
                                .foregroundColor(
                                    isSelected ? context.accentColor : Color(uiColor: .tertiaryLabel)
                                )
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: slotMetrics.slotCornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? context.accentColor : Color(uiColor: .separator).opacity(0.5),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)

                if image != nil {
                    MedicalDocumentCameraChrome.deleteButton(
                        metrics: actionMetrics
                    ) {
                        workflow.deleteSlot(slot)
                    }
                }
            }

            Text(slot.displayTitle)
                .font(.system(.caption, design: .default).weight(isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? context.accentColor : Color(uiColor: .secondaryLabel))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(height: slotMetrics.slotLabelHeight, alignment: .top)
        }
        .frame(width: width)
    }

    private func handleSlotTap(_ slot: MedicineBoxCaptureSlot) {
        if workflow.selectedSlot == slot, workflow.image(for: slot) != nil {
            onPreviewSlot(slot)
        } else {
            workflow.selectedSlot = slot
        }
    }
}
