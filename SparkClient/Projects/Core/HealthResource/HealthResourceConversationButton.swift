import SwiftUI

/// 健康资源详情页统一的快捷对话入口。
/// 入口只负责发布请求，线程创建、成员校验和草稿预览由 App 层统一编排。
struct HealthResourceConversationButton: View {
    let request: HealthResourceConversationRequest
    var isEnabled = true

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .healthResourceConversationRequested,
                object: request
            )
        } label: {
            Image(systemName: "message.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .background(Color(uiColor: .systemBackground), in: Circle())
                .shadow(radius: 4)
        }
        .disabled(isEnabled == false)
        .accessibilityLabel(L10n.text("chat.health_resource_conversation.action", fallback: "就此资料对话"))
        .accessibilityHint(L10n.text("chat.health_resource_conversation.action.hint", fallback: "打开对话并自动带入当前健康资料"))
    }
}

extension View {
    func healthResourceConversationOverlay(
        _ request: HealthResourceConversationRequest,
        isEnabled: Bool = true
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            HealthResourceConversationButton(request: request, isEnabled: isEnabled)
                .padding(.trailing, 20)
                .padding(.bottom, 28)
        }
    }
}
