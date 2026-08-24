import Foundation

/// 由任意健康资源详情页发出的“带入当前资源开启新对话”请求。
///
/// 该模型只携带资源的 canonical identity 与 Composer 所需的轻量展示快照，
/// 不复制病历正文、附件二进制或完整成员医疗数据。
struct HealthResourceConversationRequest: Equatable, Sendable {
    let identity: HealthResourceIdentity
    let displayTitle: String
    let displaySubtitle: String
    let typeBadge: String?
    let source: String

    init(
        identity: HealthResourceIdentity,
        displayTitle: String,
        displaySubtitle: String,
        typeBadge: String? = nil,
        source: String
    ) {
        self.identity = identity
        self.displayTitle = displayTitle
        self.displaySubtitle = displaySubtitle
        self.typeBadge = typeBadge
        self.source = source
    }
}

extension Notification.Name {
    static let healthResourceConversationRequested = Notification.Name(
        "spark.healthResourceConversationRequested"
    )
}
