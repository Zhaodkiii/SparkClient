import SwiftUI

struct DeepTutorCaptureCardView: View {
    let payload: DeepTutorCaptureCardPayload
    let onAction: (DeepTutorCaptureCardType, DeepTutorCaptureCardAction) -> Void

    private var spec: Spec { Spec(cardType: payload.cardType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            guide
            actionRow
            if let disclaimer = spec.disclaimer {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(spec.tint.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(spec.tint.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: spec.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(spec.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(payload.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(payload.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guide: some View {
        HStack(spacing: 8) {
            ForEach(spec.tips, id: \.self) { tip in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(spec.tint)
                    Text(tip)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(.systemBackground).opacity(0.78), in: Capsule())
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            captureButton(
                title: "拍照",
                systemImage: "camera.fill",
                action: .camera,
                emphasized: true
            )
            captureButton(
                title: "上传照片",
                systemImage: "photo.on.rectangle",
                action: .photoLibrary,
                emphasized: false
            )
            if payload.cardType.supportsFiles {
                captureButton(
                    title: "选择文件",
                    systemImage: "doc.text.fill",
                    action: .files,
                    emphasized: false
                )
            }
        }
    }

    private func captureButton(
        title: String,
        systemImage: String,
        action: DeepTutorCaptureCardAction,
        emphasized: Bool
    ) -> some View {
        Button {
            onAction(payload.cardType, action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(emphasized ? Color.white : spec.tint)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(emphasized ? spec.tint : spec.tint.opacity(0.11))
            )
        }
        .buttonStyle(.plain)
    }
}

private extension DeepTutorCaptureCardView {
    struct Spec {
        let cardType: DeepTutorCaptureCardType

        var tint: Color {
            switch cardType {
            case .reportPhoto:
                return Color.accentColor
            case .medicineBoxPhoto:
                return Color.purple
            case .skinPhoto:
                return Color.green
            }
        }

        var iconName: String {
            switch cardType {
            case .reportPhoto:
                return "doc.viewfinder"
            case .medicineBoxPhoto:
                return "cross.case.fill"
            case .skinPhoto:
                return "camera.macro"
            }
        }

        var tips: [String] {
            switch cardType {
            case .reportPhoto:
                return ["完整页面", "文字清晰", "PDF 可选"]
            case .medicineBoxPhoto:
                return ["正面拍摄", "药名清楚", "剂量可见"]
            case .skinPhoto:
                return ["光线均匀", "保持清晰", "避免滤镜"]
            }
        }

        var disclaimer: String? {
            switch cardType {
            case .reportPhoto:
                return "注：AI 提取和整理结果仅供健康管理参考，不构成诊断、治疗建议或用药依据。如需医疗帮助，请咨询医生。"
            case .medicineBoxPhoto, .skinPhoto:
                return nil
            }
        }
    }
}
