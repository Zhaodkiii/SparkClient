import SwiftUI

/// 药盒引导页内容。
struct MedicineBoxCameraGuideContent: View {
    let onDismiss: () -> Void

    private var guideItems: [(title: String, detail: String)] {
        [
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.front.title", fallback: "药盒正面"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.front.detail",
                    fallback: "拍清楚药品名称、品牌、规格、包装数量"
                )
            ),
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.expiry.title", fallback: "保质期图片"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.expiry.detail",
                    fallback: "拍清楚生产日期、有效期、批号等信息"
                )
            ),
            (
                L10n.text("home.medical.medicine_box.camera.guide.item.instruction.title", fallback: "说明书"),
                L10n.text(
                    "home.medical.medicine_box.camera.guide.item.instruction.detail",
                    fallback: "拍清楚用法用量、适应症、禁忌、注意事项"
                )
            )
        ]
    }

    private var tips: [String] {
        guideItems.map { "\($0.title)：\($0.detail)" }
    }

    var body: some View {
        MedicalDocumentCameraGuideHost(
            title: MedicalDocumentCameraContext.medicineBox.guideTitle,
            subtitle: MedicalDocumentCameraContext.medicineBox.guideSubtitle,
            disclaimer: MedicalDocumentCameraContext.medicineBox.guideDisclaimer,
            onDismiss: onDismiss
        ) {
            illustration
        } tips: {
            MedicalDocumentCameraGuideTipsCard(
                tips: tips,
                accentColor: MedicalDocumentCameraContext.medicineBox.accentColor
            )
        }
    }

    private var illustration: some View {
        let accent = MedicalDocumentCameraContext.medicineBox.accentColor
        return ZStack {
            MedicalDocumentCameraViewfinderShape(
                cornerRadiusFactor: MedicalDocumentCameraLayoutProfile.medicineBox.maskCornerRadiusFactor,
                segmentFactor: MedicalDocumentCameraLayoutProfile.medicineBox.viewfinderSegmentFactor
            )
            .stroke(
                accent,
                style: StrokeStyle(
                    lineWidth: 8,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: 200, height: 240)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.10))
                .frame(width: 150, height: 180)

            Image(systemName: "cross.case.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(accent)
        }
        .frame(width: 220, height: 280)
    }
}
