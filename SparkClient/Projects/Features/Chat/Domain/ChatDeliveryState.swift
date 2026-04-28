import Foundation

// 聊天消息 发送/送达 状态枚举
enum ChatDeliveryState: String, Codable, Sendable {
    case pending      // 待发送（已加入队列，尚未开始发送）
    case sending      // 发送中（正在上传/请求接口/流式返回）
    case sent         // 已发送（服务器已接收，消息发送成功）
    case failed       // 发送失败（网络错误/服务异常/超时）
    case read         // 已读（对方已查看消息，仅用于对话同步场景）
}
