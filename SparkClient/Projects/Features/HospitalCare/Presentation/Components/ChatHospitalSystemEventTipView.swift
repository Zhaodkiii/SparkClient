import SwiftUI

/// 线上问诊系统事件（医生接管 / 取消接管等）居中提示，对齐 Web `consult-msg-tip`。
struct ChatHospitalSystemEventTipView: View {
    let text: String
    var isMuted: Bool = false

    private var accentColor: Color {
        if isMuted {
            return Color.secondary
        }
        return Color(red: 46.0 / 255.0, green: 125.0 / 255.0, blue: 100.0 / 255.0)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(accentColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

enum ChatHospitalSystemMessageSupport {
    private static let displayPrefix = L10n.text("chat.hospital.system_event.prefix", fallback: "系统提示：")

    static func shouldRenderCenteredTip(for message: ChatMessage) -> Bool {
        guard message.role == .system else { return false }
        if message.blocks.contains(where: { $0.kind == .hospitalDoctorIntroCard || $0.kind == .chatGuideCard }) {
            return false
        }
        return plainText(from: message).isEmpty == false
    }

    static func displayText(for message: ChatMessage) -> String {
        let text = plainText(from: message)
        if text.hasPrefix(displayPrefix) {
            return text
        }
        return displayPrefix + text
    }

    static func plainText(from message: ChatMessage) -> String {
        message.blocks
            .filter { $0.kind == .text }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
