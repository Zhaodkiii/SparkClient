# CHAT-000059 WebSocket 网络断开误触发鉴权失效退出修复需求确认工单

> 工单状态：需求确认中  
> 创建日期：2026-09-04  
> 适用项目：SparkClient  
> 关联服务：SparkService `/ws/chat/sync/` 及认证接口  
> 当前阶段：先确认方案，不修改业务代码

## 1. 问题背景

客户端在聊天实时 WebSocket 连接断开时，将普通网络连接错误误判为服务端鉴权失效，触发全局退出登录。用户因此被清除 Token、SessionSnapshot 和账号运行时状态，回到登录页。

## 2. 现场日志证据

本次日志中出现：

```text
WebSocket: NSPOSIXErrorDomain Code=57 Socket is not connected
HTTP: NSURLErrorDomain Code=-1005 网络连接已中断
```

随后客户端执行：

```text
收到服务端鉴权失效事件
AppSessionStore：设置未登录状态
认证仓储：开始登出
清除 Keychain token 与 SessionSnapshot
```

关键判断：`Code=57` 和 `-1005` 是连接/传输层错误，不等价于 Token 失效。日志中的 Logout 请求失败是退出流程启动后的结果，不是误退出的根因。

## 3. 当前代码事实

### 3.1 WebSocket 断开处理

文件：

```text
SparkClient/SparkClient/Projects/Features/Chat/Infrastructure/ChatRealtimeSyncClient.swift
```

当前 `handle(event:)` 在 `.disconnected` 分支中调用 `shouldInvalidateSessionOnDisconnect(reason:)`。该方法除识别 `4401` 外，还把断开原因继续传给 `shouldInvalidateSession(for:)`。

### 3.2 当前误判点

当前实现：

```swift
private static func shouldInvalidateSession(for message: String) -> Bool {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.isEmpty == false else { return false }
    return AuthSessionInvalidation.shouldInvalidate(
        statusCode: 401,
        backendCode: nil,
        message: normalized
    )
}
```

这里把任意 WebSocket 断开文本强行传入 `statusCode: 401`。而 `AuthSessionInvalidation.shouldInvalidate` 只要收到 401 就返回 `true`，因此普通的 `Socket is not connected`、网络中断、服务端主动断开等原因都可能被当成鉴权失败。

### 3.3 全局退出链路

当前明确存在以下链路：

```text
ChatRealtimeSyncClient
  → AuthSessionInvalidation.postIfNeeded
  → RouteCoordinator / AppLifecycleCoordinator
  → AppSessionStore.signedOut
  → AuthRepository.logout
  → AuthTokenProvider 清理 Token
  → SessionSnapshotStore 清理快照
```

关键文件：

- `Projects/Core/Networking/SparkNetworkModels.swift`
- `Projects/Core/Networking/WebSocket/SparkWebSocketClient.swift`
- `Projects/Features/Chat/Infrastructure/ChatRealtimeSyncClient.swift`
- `Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift`
- `Projects/App/Sources/App/Architecture/RouteCoordinator.swift`
- `Projects/Core/Networking/AuthTokenProvider.swift`
- `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift`

## 4. 已知偏差与风险

| 偏差 | 当前表现 | 风险 |
| --- | --- | --- |
| 传输错误伪造 401 | 断开原因被送入 `statusCode: 401` | 普通断网触发退出登录 |
| WebSocket 断开与 HTTP 401 共用判定入口 | 没有结构化 close code 时按文本猜测 | 错误文本造成误登出 |
| 连接失败和鉴权失败共用退出动作 | connect/disconnect 失败可能 post invalidation | 网络抖动清除账号态 |
| Logout 失败仍继续本地清理 | 当前是既定登出行为 | 误触发后用户需要重新登录 |
| 测试重点不足 | 未覆盖 Code 57、-1005 等真实断开错误 | 回归无法阻止再次发生 |

## 5. 初步修复目标

1. 普通 WebSocket 网络断开、连接失败、超时和重连不得触发退出登录。
2. 只有服务端提供明确的鉴权失效证据时，才允许进入全局 `signedOut` 流程。
3. WebSocket 断开继续执行退避重连和必要的同步补偿。
4. HTTP 请求已有 401/明确 Token 失效仍按现有刷新/失效流程处理。
5. 不改变普通 403 权限失败、业务失败和网络失败的现有语义。
6. 不修改历史会话、聊天消息和服务器端数据。

## 6. 初步修复边界

### 6.1 可以触发全局退出的证据

初步限定为：

- HTTP 响应状态明确为 401，且属于需要失效处理的鉴权请求结果；
- WebSocket 明确收到结构化的认证失效事件，例如 `auth.session.invalidated`；
- WebSocket 明确收到认证关闭码，例如 4401，并且关闭码来自结构化 close code，而不是普通错误文案；
- Refresh Token 明确被服务端拒绝，且现有 Token 刷新流程已确认无法恢复。

### 6.2 不可以触发全局退出的错误

- `NSPOSIXErrorDomain Code=57`；
- `NSURLErrorDomain Code=-1005`；
- `URLError.notConnectedToInternet`；
- DNS、连接超时、TLS 连接中断、连接重置；
- WebSocket 无 close code 的普通断开；
- WebSocket 自动重连失败；
- 普通 403 业务权限失败；
- 聊天同步接口暂时不可用。

## 7. 初步状态流转

```text
WebSocket 连接断开
       │
       ├─ 结构化 close code = 4401？──是──→ 认证失效判定
       │
       ├─ 收到 auth.session.invalidated？──是──→ 认证失效判定
       │
       └─ 其他网络/传输错误 ───────────→ disconnected → 退避重连
                                             │
                                             └─ 不清 Token、不改 signedOut
```

## 8. 当前非目标

- 本工单不修改服务端 WebSocket 协议，除非后续确认现有 close code 无法提供明确鉴权证据。
- 不重新设计登录、Token 刷新和账号切换流程。
- 不因为网络断开增加前台强制登录提示。
- 不删除现有 WebSocket 自动重连机制。
- 不在未确认前直接修改代码。

## 9. 当前关键文件

| 文件 | 当前职责 | 预计改造方向 |
| --- | --- | --- |
| `Projects/Features/Chat/Infrastructure/ChatRealtimeSyncClient.swift` | WebSocket 连接、事件解析、断开和重连 | 只允许结构化鉴权证据触发失效；普通断开只重连 |
| `Projects/Core/Networking/SparkNetworkModels.swift` | 统一网络错误与鉴权失效判定 | 保持 HTTP/Refresh 判定，禁止传输错误伪造 401 |
| `Projects/Core/Networking/WebSocket/SparkWebSocketClient.swift` | WebSocket 连接事件和断开原因 | 如当前未返回 close code，补充结构化 close code 传递 |
| `Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift` | 全局会话状态切换 | 只接收明确失效事件 |
| `Projects/App/Sources/App/Architecture/RouteCoordinator.swift` | 路由重置 | 不处理普通断线 |
| `Projects/Core/Networking/AuthTokenProvider.swift` | Token 保存、刷新和清理 | 不因 WebSocket 传输失败清理 |
| `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift` | 登出和恢复会话 | 保持显式登出/明确失效逻辑 |
| `需求文档/对话/CHAT-000056-医生Web消息应用内实时更新需求工单.md` | WebSocket 实时同步既有方案 | 补充与本工单一致的断线/鉴权边界引用 |

## 10. 一问一答确认记录

### 第 1 问：WebSocket 断开时，什么条件才允许触发全局鉴权失效？

为什么要问：这是本次误退出的核心边界。若继续把断开原因当作 401，任何网络波动都可能清除账号；若完全不处理 WebSocket 鉴权失效，又会导致 Token 已被服务端撤销后客户端继续重连。

请选择：

- A. 只有结构化认证失效事件或明确 WebSocket 鉴权关闭码才触发；普通断开只重连（推荐）  
  `auth.session.invalidated`、结构化 close code `4401` 和既有 HTTP/Refresh 明确 401 继续触发失效；Code 57、-1005、超时和无 close code 断开全部走重连。

- B. 任何 WebSocket 断开都触发一次 Token 刷新，刷新失败后再退出  
  可以尝试恢复，但网络断开时会产生额外刷新请求；若刷新请求也受网络影响，仍可能把暂时故障误判为账号失效。

- C. WebSocket 永远不触发全局鉴权失效，只由 HTTP 请求判断  
  能完全避免误退出，但服务端主动撤销会话后，客户端实时连接可能长期带着失效状态重连。

- D. 继续根据断开 reason 文本判断是否鉴权失效，并把断开视为 401 语义  
  改动最小，但无法区分传输错误与认证错误，正是当前问题的来源。

请选择 A、B、C 或 D。

#### 第 1 问确认

**已确认选择 C：WebSocket 永远不触发全局鉴权失效，只由 HTTP 请求判断。**

落地约束：

- `ChatRealtimeSyncClient` 的 WebSocket `.disconnected`、连接失败和自动重连失败全部只进入断线/重连状态，不调用 `AuthSessionInvalidation.postIfNeeded`，不改变 `AppSessionStore`，不清理 Token 或 SessionSnapshot。
- WebSocket 收到文本事件时也不再触发全局鉴权失效；包括 `auth.session.invalidated`、`device_session.*` 或文本中的鉴权失败信息，均不在本工单中驱动退出登录。
- WebSocket 仍可记录脱敏断线原因、执行退避重连和恢复后的同步补偿；不得因为重连长期失败而清除账号。
- 全局鉴权失效的唯一入口收敛到 HTTP 请求和 Token Refresh 流程；后续 HTTP 401 的处理规则由第 2 问确认。
- 该选择意味着服务端主动撤销会话后，WebSocket 可能继续尝试重连；每次重连仍需使用当前 `AuthTokenProvider` 的 Token，HTTP API 一旦明确返回 401，再进入既有刷新/失效流程。

### 第 2 问：HTTP 请求收到 401 时，Token 刷新与退出登录应如何处理？

为什么要问：不能因为修复 WebSocket 误退出而放宽 HTTP 鉴权处理。Access Token 自然过期时应优先刷新并重试；只有 Refresh Token 明确失效或刷新确认无法恢复时，才能清理会话并回到登录页。

请选择：

- A. 401 先强制刷新 Token 并只重试原请求一次；Refresh 明确失败后才全局退出（推荐）  
  复用现有 `AuthTokenProvider` 去重刷新和 `SparkNetworkEngine` 重试逻辑，避免短期 Token 过期直接登出。

- B. 任意 HTTP 401 立即清除 Token 并退出登录  
  逻辑简单，但会把 Access Token 过期、服务端时钟偏差或一次性请求问题误判为不可恢复失效。

- C. HTTP 401 无限刷新直到请求成功  
  可能造成刷新死循环、请求风暴和账号状态无法收敛。

- D. HTTP 401 只提示请求失败，不刷新也不退出  
  可以避免误退出，但 Token 失效后账号会一直处于不可用状态。

请选择 A、B、C 或 D。

#### 第 2 问确认

**已确认选择 A：401 先强制刷新 Token 并只重试原请求一次；Refresh 明确失败后才全局退出。**

落地约束：

- 已鉴权 HTTP 请求收到 401 时，继续复用 `SparkNetworkEngine` 的一次刷新/重试逻辑，并由 `AuthTokenProvider` 对并发刷新任务去重。
- 刷新成功后只重试原请求一次；重试仍返回 401 时，按明确不可恢复的鉴权失败处理，不再循环刷新。
- Refresh Token 明确被服务端拒绝、明确过期、撤销或设备会话失效时，才调用全局鉴权失效流程。
- 网络断开、连接超时、DNS/TLS 错误和服务暂不可用不等于 Refresh 明确失败；其处理由第 3 问确认。
- WebSocket 仍不参与这条全局退出判断链路。

### 第 3 问：Token Refresh 请求遇到网络错误时，客户端应如何处理？

为什么要问：即使 HTTP 401 触发了刷新，Refresh 请求也可能遇到与本次问题相同的 `Code=57`、`-1005`、超时或服务暂不可用。如果把刷新失败的所有错误都当成 Token 失效，仍会出现网络断开导致意外退出。

请选择：

- A. 网络错误不退出登录，保留当前会话状态并按退避策略稍后重试（推荐）  
  只把明确的 Refresh 401/业务失效码视为不可恢复；网络恢复后再刷新，期间页面显示网络异常或暂不可用。

- B. Refresh 任意失败都立即退出登录  
  实现简单，但会把短暂网络故障直接变成账号退出。

- C. Refresh 网络失败时使用旧 Access Token 无限重试原请求  
  可能形成请求风暴；旧 Token 已经收到 401，不能无限重复使用。

- D. Refresh 网络失败时自动创建游客会话并切换运行时  
  会造成登录账号与游客账号状态混淆，且可能导致数据和页面上下文错误切换。

请选择 A、B、C 或 D。

#### 第 3 问确认

**已确认选择 A：网络错误不退出登录，保留当前会话状态并按退避策略稍后重试。**

落地约束：

- Refresh 遇到 `Code=57`、`-1005`、无网络、超时、DNS/TLS 或服务暂不可用时，`AppSessionStore` 保持当前登录态，不清理 Token、SessionSnapshot 或账号运行时。
- 当前原请求返回可重试的网络错误；不无限重试，不把旧 Access Token 无限重复发送。
- Refresh 重试使用指数退避和上限；网络恢复、App 回前台或下一次需要鉴权请求时可重新触发一次去重刷新。
- 只有 Refresh 收到明确的 401/失效业务码，或本地确认 Refresh Token 不存在且无法恢复时，才进入全局鉴权失效流程。
- WebSocket 断开仍只负责重连，不改变上述 Refresh 规则。

### 第 4 问：普通 HTTP 403 权限失败时，客户端是否保持当前登录状态？

为什么要问：权限不足、成员无权、资源不可见与登录凭证失效不是同一类问题。若把 403 当作 401 处理，用户会被错误退出；如果把 403 继续当作可重试鉴权失败，还可能造成请求循环。

请选择：

- A. 保持登录状态，只展示权限不足或业务无权提示，不刷新 Token、不退出登录（推荐）  
  复用现有 `AuthSessionInvalidation.shouldInvalidate` 对 403 不触发失效的语义；用户可以继续使用其他有权限的功能。

- B. 403 先刷新 Token，刷新失败后退出登录  
  403 通常表示权限判断而不是 Access Token 过期，刷新不能解决资源授权问题。

- C. 任意 403 立即退出登录  
  会把成员权限、资源权限和账号登录状态混为一谈，造成误退出。

- D. 403 自动切换游客或其他账号运行时  
  会污染当前账号上下文，并可能造成数据展示和权限边界错误。

请选择 A、B、C 或 D。

#### 第 4 问确认

**已确认选择 A：保持登录状态，只展示权限不足或业务无权提示，不刷新 Token、不退出登录。**

落地约束：

- HTTP 403 只作为业务授权失败处理，保持 `AppSessionStore` 当前登录态。
- 不调用 Token Refresh，不清理 Keychain Token、SessionSnapshot 或账号运行时。
- 当前请求结束并向页面返回权限错误；不自动重试同一请求，不切换游客或其他账号。
- 与现有 `AuthSessionInvalidation.shouldInvalidate` 语义保持一致：403 不触发全局鉴权失效。
- 如果服务端确实需要撤销账号，会通过 HTTP 401/明确 Refresh 失效结果表达，不依赖普通 403。

### 第 5 问：WebSocket 收到鉴权相关事件文本时，客户端应如何处理？

为什么要问：第 1 问已经确认 WebSocket 不触发全局退出，但现有代码仍会解析 `auth.session.invalidated`、`device_session.*` 和鉴权失败文本。若只删除退出动作却不定义后续行为，客户端可能反复重连、重复提示或把事件误当作聊天同步消息。

请选择：

- A. 记录脱敏诊断信息并进入普通断线重连，不改变登录态（推荐）  
  WebSocket 事件只作为实时通道状态处理；连接关闭或异常后按退避策略重连，账号继续保持登录，真正的 HTTP 鉴权结果由 HTTP 链路处理。

- B. 收到事件后立即停止 WebSocket，直到 App 重新登录才恢复  
  可以避免重复连接，但会让实时同步长期失效，也把 WebSocket 事件间接变成退出门控。

- C. 收到事件后刷新 Token，再重新连接 WebSocket  
  会让 WebSocket 重新参与认证处理，且可能在网络异常时制造刷新请求风暴。

- D. 将鉴权事件当作普通 `chat.sync.updated` 处理并拉取消息  
  事件语义不同，可能产生无意义同步和错误 UI 更新。

请选择 A、B、C 或 D。

#### 第 5 问确认

**已确认选择 A，并补充收敛为：WebSocket 鉴权相关事件不做其他特殊处理，统一进入普通断线重连，不改变登录态。**

落地约束：

- WebSocket 收到 `auth.session.invalidated`、`device_session.*` 或包含鉴权文字的消息时，不触发 `AuthSessionInvalidation`，不刷新 Token，不清理本地会话，不退出登录，不向用户展示鉴权失效提示。
- 这类事件不作为聊天同步事件处理，不触发消息拉取；连接关闭后按普通实时通道断线进入退避重连。
- 不新增针对该事件的独立业务处理、弹窗、Toast、账号状态变更或本地数据清理。
- 真正的 HTTP 401、Refresh 明确失效和其他 HTTP 鉴权结果继续由 HTTP 链路处理。

### 第 6 问：WebSocket 初次连接或重连建立失败时，应如何处理？

为什么要问：当前 `connectIfNeeded()` 的 `catch` 分支也会把连接错误文本传入鉴权失效判断；即使修复 `.disconnected`，初次连接遇到网络错误仍可能触发退出登录。

请选择：

- A. 所有 WebSocket 连接建立失败都只进入普通断线重连，不改变登录态（推荐）  
  `connect()`、`makeRequest()`、连接超时、DNS/TLS、网络中断和 Socket 错误统一记录为实时通道失败；不调用全局鉴权失效流程。

- B. 连接建立失败先刷新 Token，刷新失败后退出登录  
  会让实时通道再次参与鉴权判断，并可能在网络不可用时触发刷新风暴。

- C. 连接建立失败立即退出登录  
  与普通网络错误无关地清除账号状态，正是本次问题需要修复的行为。

- D. 连接建立失败停止所有重连，等待用户手动重新登录  
  会让实时同步因一次网络抖动永久停止，且仍把网络问题呈现为登录问题。

请选择 A、B、C 或 D。

#### 第 6 问确认

**已确认选择 A：所有 WebSocket 连接建立失败都只进入普通断线重连，不改变登录态。**

落地约束：

- `connect()`、`makeRequest()`、连接超时、DNS/TLS、网络中断、Socket 错误和其他连接建立异常统一视为实时通道失败。
- `connectIfNeeded()` 的失败分支不得调用 `AuthSessionInvalidation.postIfNeeded`，不得切换 `AppSessionStore.signedOut`，不得清理 Token、SessionSnapshot 或账号运行时。
- 连接失败按照现有退避策略重连；重连任务失败仍继续退避，不转化为登录失效。
- WebSocket 的认证消息和断开 reason 也不参与全局鉴权失效判断；全局鉴权失效只由 HTTP/Refresh 链路判定。
- 本次修复重点是拆除 WebSocket 到全局退出流程的连接，不改变普通 HTTP 401 的刷新和最终失效语义。

## 11. 最终确认结论汇总

| 编号 | 最终结论 | 落地影响 |
| --- | --- | --- |
| C-001 | WebSocket 永远不触发全局鉴权失效 | 断开、连接失败、鉴权文本和重连失败都不退出登录 |
| C-002 | HTTP 401 先强制刷新 Token，原请求只重试一次 | 复用 `AuthTokenProvider` 和 `SparkNetworkEngine` 现有刷新链路 |
| C-003 | Refresh 网络错误不退出登录 | 保留会话，按退避策略稍后刷新，不清理本地认证状态 |
| C-004 | HTTP 403 保持登录 | 只展示权限/业务错误，不刷新 Token，不退出登录 |
| C-005 | WebSocket 鉴权相关事件不做特殊处理 | 不刷新、不提示、不清理、不触发消息同步，统一断线重连 |
| C-006 | WebSocket 初次连接和重连建立失败统一普通重连 | `makeRequest()`、`connect()`、超时、DNS/TLS、Socket 错误均不触发登出 |

## 12. 修复后的完整业务流程

### 12.1 WebSocket 正常连接

```text
账号已登录
    │
    └─ ChatRealtimeSyncClient.start()
          │
          ├─ makeRequest() 获取当前 Authorization
          │
          ├─ connect() 成功
          │     ├─ 标记实时通道 connected
          │     ├─ 重置 reconnectAttempt
          │     └─ 触发既有同步补偿
          │
          └─ connect() 失败
                └─ 普通断线重连，不改变账号登录态
```

### 12.2 WebSocket 普通网络断开

```text
WebSocket disconnected
    │
    ├─ Code=57 / Socket is not connected
    ├─ -1005 / 网络连接已中断
    ├─ timeout / DNS / TLS / connection reset
    ├─ 无 close code
    └─ 其他非结构化 reason
          │
          ├─ 记录脱敏实时通道状态
          ├─ 进入 disconnected
          ├─ 退避重连
          └─ 保持 signedIn，不清 Token，不清 SessionSnapshot
```

### 12.3 WebSocket 收到鉴权相关消息

```text
收到 WebSocket 文本事件
    │
    ├─ type = auth.session.invalidated？
    ├─ type = device_session.*？
    ├─ msg 包含 token/auth 文字？
    └─ 其他文本？
          │
          └─ 均不做鉴权特殊处理
                ├─ 不 post AuthSessionInvalidation
                ├─ 不刷新 Token
                ├─ 不改变 signedIn/signedOut
                ├─ 不触发消息同步
                └─ 连接异常时按普通断线重连
```

### 12.4 HTTP 401

```text
普通鉴权 HTTP 请求返回 401
    │
    ├─ AuthTokenProvider 强制刷新 Token
    │     ├─ 刷新成功 → 原请求只重试一次
    │     ├─ 原请求成功 → 返回业务结果
    │     ├─ 原请求再次 401 → 明确不可恢复，进入失效流程
    │     └─ 刷新网络错误 → 保持登录，按退避重试
    │
    └─ Refresh 明确 401/失效业务码
          └─ 清理 Token/SessionSnapshot → signedOut
```

### 12.5 HTTP 403

```text
HTTP 403
    │
    ├─ 保持当前登录态
    ├─ 不刷新 Token
    ├─ 不退出登录
    ├─ 不自动重试
    └─ 返回权限不足/业务无权状态给页面
```

## 13. 服务端与客户端职责边界

### 13.1 服务端职责

本工单原则上不要求修改服务端 WebSocket 协议。服务端如果返回普通连接关闭、网络中断或空 close code，客户端都按普通断线处理。

如果后续服务端需要表达会话撤销，必须通过现有 HTTP 鉴权链路明确返回 401 或明确 Refresh 失效业务码；不能依赖 WebSocket 文本让客户端触发全局退出。

### 13.2 iOS 客户端职责

- WebSocket 只负责实时同步通知、连接状态和重连。
- HTTP 网络层负责 HTTP 状态、Refresh 和全局认证失效判定。
- `AuthSessionInvalidation` 不再接收 WebSocket 来源事件。
- 普通网络错误只能产生可重试的 transport 状态。
- 页面和账号状态不得从 WebSocket 的断线 reason 推导登录状态。

## 14. 关键代码改造方案

### 14.1 `ChatRealtimeSyncClient.swift`

当前问题是两条路径都把 WebSocket 错误送进鉴权失效：

1. `connectIfNeeded()` 的 `catch` 分支调用 `shouldInvalidateSession(for:)`。
2. `.disconnected` 分支调用 `shouldInvalidateSessionOnDisconnect(reason:)`。
3. `.text` 分支调用 `shouldInvalidateSession(in:)`。

按最终结论，三条路径都应删除“触发全局鉴权失效”的行为，保留连接状态、普通日志和重连行为。

方案级伪代码：

```swift
private func connectIfNeeded() async {
    guard isRunning else { return }

    do {
        var request = try await makeRequest()
        request.timeoutInterval = 20
        await socket.connect(request: request) { [weak self] event in
            guard let self else { return }
            Task { await self.handle(event: event) }
        }
    } catch {
        // 任何 WebSocket 建连错误都只是实时通道失败
        logger.warning(
            "chat realtime connect failed: \(redactedTransportReason(error))",
            module: .general
        )
        scheduleReconnect()
    }
}
```

`.text` 和 `.disconnected` 的方案级处理：

```swift
private func handle(event: SparkWebSocketEvent) async {
    guard isRunning else { return }

    switch event {
    case .connected:
        reconnectAttempt = 0
        connectedHandler?()

    case .text(let text):
        guard let hint = parseSyncHintIfApplicable(text) else {
            // 鉴权文本、未知文本都不进入全局认证流程
            return
        }
        hintHandler?(hint)

    case .disconnected(let reason):
        logger.warning(
            "chat realtime disconnected: \(redactedReason(reason))",
            module: .general
        )
        scheduleReconnect()
    }
}
```

说明：以上是方案级伪代码，不是当前代码修改。`parseSyncHintIfApplicable` 只允许识别 `chat.sync.updated`；未知消息和鉴权相关消息直接忽略，不转成同步提示，也不发出退出事件。

### 14.2 删除或废弃 WebSocket 鉴权判定方法

以下方法不能继续作为 WebSocket 的退出入口：

```swift
shouldInvalidateSession(in:)
shouldInvalidateSession(for:)
shouldInvalidateSessionOnDisconnect(reason:)
isWebSocketAuthCloseCode(_:)
postAuthSessionInvalidation(message:source:)
```

处理方式有两种，最终实现时应统一选择一种：

- 删除仅被 WebSocket 使用的鉴权判定方法；
- 保留通用 HTTP 使用的方法，但从 `ChatRealtimeSyncClient` 完全移除调用。

不能保留“传入 `statusCode: 401` 再根据文本判断”的兼容逻辑，因为这正是当前误判根因。

### 14.3 `SparkNetworkModels.swift`

`AuthSessionInvalidation.shouldInvalidate(statusCode:backendCode:message:)` 继续服务 HTTP 与 Refresh，不建议为了修 WebSocket 而放宽 HTTP 认证规则。

方案边界：

```swift
// HTTP/Refresh 链路可以调用
AuthSessionInvalidation.postIfNeeded(
    statusCode: httpStatus,
    backendCode: backendCode,
    message: backendMessage,
    source: "HTTP..."
)

// ChatRealtimeSyncClient 不得调用
AuthSessionInvalidation.postIfNeeded(... source: "ChatRealtimeSyncClient...")
```

如需从结构上防止误用，可将 WebSocket 事件类型与 HTTP 鉴权失效事件分为不同 API；但这是可选的结构性增强，不是本期必须新增的业务协议。

### 14.4 `SparkWebSocketClient.swift`

如果底层 WebSocket 只返回字符串 reason，建议后续补充结构化 close code，但本工单最终结论仍是“WebSocket 不触发全局退出”，因此 close code 只用于：

- 诊断；
- 连接状态展示；
- 重连策略；
- 统计监控。

即使 close code 为 4401，也不能在本工单中直接触发 `signedOut`。

## 15. 网络错误分类

### 15.1 传输错误

统一映射为 `SparkNetworkError.transport` 或等价实时通道错误：

- `NSPOSIXErrorDomain Code=57`；
- `NSURLErrorDomain Code=-1005`；
- `URLError.notConnectedToInternet`；
- `URLError.timedOut`；
- DNS 失败；
- TLS 握手失败；
- 连接被重置；
- Socket 未连接；
- 无结构化 HTTP 响应。

这些错误永远不能触发 `AuthSessionInvalidation`。

### 15.2 HTTP 鉴权错误

只有明确属于 HTTP/Refresh 的以下结果才允许进入鉴权流程：

- HTTP 401；
- Refresh Token 明确无效；
- Refresh Token 明确过期；
- 服务端明确返回设备会话撤销业务码；
- 服务端明确返回不可恢复认证业务码。

即便 HTTP 401 触发，也必须先执行一次 Token Refresh 和原请求重试，除非该响应本身来自 Refresh 且已明确不可恢复。

### 15.3 HTTP 403

HTTP 403 统一视为权限/业务拒绝：

- 不退出；
- 不刷新；
- 不清理账号态；
- 不自动重试；
- 返回页面处理。

## 16. 重连与 Refresh 并发控制

### 16.1 WebSocket 重连

继续复用现有重连策略：

```text
第 1 次：1 秒
第 2 次：2 秒
第 3 次：4 秒
第 4 次：8 秒
后续：最高 30 秒
```

要求：

- 同一时间最多一个 `reconnectTask`；
- `stop()` 后不得继续重连；
- 账号切换/显式登出时取消重连任务；
- 重连失败不改变账号状态；
- 重连成功重置次数并触发既有同步补偿；
- 旧账号重连任务不得写入新账号状态。

### 16.2 Token Refresh

- 继续使用 `AuthTokenProvider` 的并发刷新去重；
- 同一时间只保留一个 Refresh 请求；
- Refresh 网络失败不清理 Token；
- Refresh 明确失效才发布认证失效事件；
- 原请求最多重试一次；
- 不将 WebSocket 重连作为 Refresh 触发器。

## 17. 日志与敏感信息

### 17.1 允许记录

- WebSocket 连接状态：connecting/connected/disconnected/reconnecting；
- 脱敏错误类型：transport、timeout、dns、tls、socket；
- 重连次数；
- request ID 或 connection ID；
- HTTP 状态码和脱敏业务码；
- 认证失效来源必须标记为 HTTP/Refresh，不标记为 WebSocket。

### 17.2 禁止记录

- Access Token；
- Refresh Token；
- Authorization Header；
- Cookie；
- WebSocket 完整鉴权 payload；
- 患者健康资料；
- 聊天正文；
- 完整错误响应中可能包含的认证凭证。

### 17.3 诊断字段建议

```text
source=chat_realtime
event=disconnected
transport_error=socket_not_connected
network_code=57
auth_invalidation_emitted=false
reconnect_scheduled=true
account_generation=<opaque>
```

其中 `auth_invalidation_emitted=false` 可用于回归验证，但不能包含 Token 或用户敏感信息。

## 18. 测试与验收方案

### 18.1 必须通过的核心测试

| 场景 | 预期结果 |
| --- | --- |
| WebSocket Code 57 | 不退出，进入重连 |
| WebSocket -1005 | 不退出，进入重连 |
| 无网络后 WebSocket 建连失败 | 不退出，退避重连 |
| DNS 失败 | 不退出，退避重连 |
| TLS 连接失败 | 不退出，退避重连 |
| Socket 未连接 | 不退出，退避重连 |
| WebSocket 无 close code 断开 | 不退出，退避重连 |
| WebSocket 收到鉴权文本 | 不刷新、不提示、不退出，按普通通道处理 |
| WebSocket 收到 `auth.session.invalidated` | 不改变登录态，不清 Token |
| HTTP 401 + Refresh 成功 | 更新 Token，原请求只重试一次 |
| HTTP 401 + Refresh 网络失败 | 保持登录，按退避稍后重试 |
| HTTP 401 + Refresh 明确失效 | 清理会话并进入登录页 |
| HTTP 403 | 保持登录，展示权限错误 |
| 显式用户登出 | 正常清理并回登录页 |

### 18.2 回归测试伪代码

```swift
func testWebSocketTransportFailureDoesNotInvalidateSession() async {
    await realtimeClient.handle(
        event: .disconnected("Socket is not connected")
    )

    XCTAssertTrue(sessionStore.isSignedIn)
    XCTAssertFalse(authInvalidationRecorder.didPost)
    XCTAssertTrue(reconnectScheduler.didSchedule)
    XCTAssertFalse(tokenProvider.didClearTokens)
}

func testHTTP401RefreshesAndRetriesOnce() async throws {
    server.enqueue401()
    server.enqueueRefreshSuccess()
    server.enqueueSuccess()

    _ = try await networkEngine.perform(request)

    XCTAssertEqual(server.originalRequestCount, 2)
    XCTAssertEqual(server.refreshRequestCount, 1)
    XCTAssertFalse(sessionStore.isSignedOut)
}

func testRefreshTransportFailureKeepsSession() async {
    server.enqueue401()
    server.enqueueTransportFailure(.networkConnectionLost)

    let result = await networkEngine.performSafely(request)

    XCTAssertTrue(result.isRetryableNetworkFailure)
    XCTAssertTrue(sessionStore.isSignedIn)
    XCTAssertFalse(authInvalidationRecorder.didPost)
}
```

以上为方案级测试示例，不是当前代码修改；真实测试需适配现有测试夹具和依赖注入方式。

### 18.3 日志回归

使用本次现场错误样本回放时，必须确认：

- 出现 `Code=57` 后没有 `AuthSessionInvalidation`；
- 出现 `-1005` 后没有 `AppSessionStore.signedOut`；
- 没有调用本地 Token 清理；
- WebSocket 重连任务被创建；
- Logout API 不会被自动触发；
- HTTP Refresh 网络错误也不触发退出。

## 19. 关键文件与实施任务拆分

### 19.1 iOS 网络与实时通道

1. `Projects/Features/Chat/Infrastructure/ChatRealtimeSyncClient.swift`  
   删除 WebSocket 连接、文本事件、断开分支到全局鉴权失效的调用；保留重连和同步提示。
2. `Projects/Core/Networking/WebSocket/SparkWebSocketClient.swift`  
   检查断开 reason 传递；如补充 close code，仅用于诊断和重连，不触发退出。
3. `Projects/Core/Networking/SparkNetworkModels.swift`  
   保持 HTTP/Refresh 鉴权判定；增加或完善传输错误永不失效的测试。
4. `Projects/Core/Networking/SparkNetworkEngine.swift`  
   验证 401 刷新、原请求单次重试和网络失败不登出逻辑。
5. `Projects/Core/Networking/AuthTokenProvider.swift`  
   验证并发 Refresh 去重和明确失效清理边界，不新增 WebSocket 调用。

### 19.2 App 生命周期与认证

1. `Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift`  
   确认只处理 HTTP/Refresh 发布的认证失效通知。
2. `Projects/App/Sources/App/Architecture/RouteCoordinator.swift`  
   确认普通实时断线不触发 route graph reset。
3. `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift`  
   保持显式登出和明确认证失败清理；不接收 WebSocket transport failure。
4. `Projects/Core/Device/Application/DeviceRegistrationCoordinator.swift` 与 `RegisterDeviceUseCase.swift`  
   保持设备登记 HTTP 401/明确业务失效处理，不把设备登记普通网络失败升级为退出。

## 20. 核心状态模型

建议将实时通道状态与账号会话状态分开：

```swift
enum RealtimeConnectionState: Equatable {
    case stopped
    case connecting
    case connected
    case disconnected(reason: String?)
    case reconnecting(attempt: Int)
}

enum AppSessionState {
    case signedOut
    case signedIn
}
```

允许的状态关系：

```text
signedIn + connected
signedIn + disconnected
signedIn + reconnecting
signedIn + HTTP refresh pending
signedIn + HTTP retryable network failure

signedOut only after:
  explicit logout
  HTTP/Refresh explicit unrecoverable auth failure
```

禁止关系：

```text
WebSocket disconnected → signedOut
WebSocket connect failed → signedOut
WebSocket auth text → signedOut
Code=57 → signedOut
-1005 → signedOut
HTTP 403 → signedOut
Refresh network timeout → signedOut
```

## 21. 兼容与迁移说明

- 不迁移历史聊天数据。
- 不修改服务端消息、Thread、同步 cursor 或 WebSocket 事件存储。
- 不修改用户现有登录方式。
- 不修改普通 Pro、医院医生智能体或知识库业务。
- 只收敛客户端错误分类和退出触发来源。
- 现有已经处于 signedOut 的用户不会自动恢复；修复后新发生的网络断线不应再次造成退出。
- 旧版本客户端仍可能存在误判，服务端无需为旧客户端修改业务数据；发布新客户端后通过版本分布和错误日志观察回归效果。

## 22. 实施顺序

### 阶段一：锁定判定边界

1. 确认 `AuthSessionInvalidation` 的 HTTP/Refresh 调用方。
2. 列出所有 `ChatRealtimeSyncClient` 到 `AuthSessionInvalidation` 的调用点。
3. 将 WebSocket 三条路径标记为普通实时通道失败。

### 阶段二：修改实时通道

1. 移除 `connectIfNeeded()` catch 中的鉴权失效判断。
2. 移除 `.disconnected` 中的鉴权失效判断。
3. 移除 `.text` 中的鉴权事件退出判断。
4. 保留断线日志、指数退避和连接成功补偿。

### 阶段三：验证 HTTP 鉴权链路

1. 验证 HTTP 401 仍会触发一次 Refresh。
2. 验证原请求最多重试一次。
3. 验证 Refresh 网络失败不退出。
4. 验证 Refresh 明确失效才退出。
5. 验证 403 不退出。

### 阶段四：回归与发布

1. 回放 Code 57、-1005 和无网络场景。
2. 验证账号状态、Token、SessionSnapshot 不被清理。
3. 验证 WebSocket 重连和聊天同步补偿仍可用。
4. 验证显式登出和真实 HTTP 鉴权失效仍正常。
5. 发布后监控 `auth_invalidation source=ChatRealtimeSyncClient`，目标应为 0。

## 23. 完成定义

本工单达到完成的条件：

- WebSocket 任何断开或连接失败都不会调用全局鉴权失效流程；
- `Code=57`、`-1005`、无网络、超时、DNS/TLS 错误均只触发重连；
- WebSocket 鉴权相关文本不触发退出、刷新、提示或同步；
- HTTP 401 的 Refresh 和单次重试保持正常；
- Refresh 网络异常保持登录；
- Refresh 明确失效仍能回到登录页；
- HTTP 403 保持登录；
- Token、SessionSnapshot 和账号运行时不会被普通网络异常清理；
- 所有核心测试和现场日志回归通过。

## 24. 交付边界

本工单已经完成问题分析、问答确认和完整落地设计，但当前未修改任何业务代码。后续实现应严格按照最终确认结论执行；若要改变“WebSocket 永远不触发全局鉴权失效”的边界，必须重新创建工单确认，不得在实现中自行恢复 WebSocket 退出逻辑。
