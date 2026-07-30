# Token 刷新需求

> 文档定位：说明 iOS 客户端当前的 Access Token 生命周期、刷新与强制退出边界。代码事实优先；本模块的关键产品语义是：**Access Token 到期本身不退出登录**。

## 一、模块目标

客户端使用短期 Access Token 发起已鉴权请求，并持有 Refresh Token 续期。目标是在网络正常、Refresh Token 仍有效时无感续期，避免用户因 Access Token 自然到期被迫重新登录。

模块负责令牌的内存/Keychain 保存、到期前刷新、401 后强制刷新重试、刷新并发去重，以及服务端明确确认认证已失效时发布全局事件。模块不负责登录页面、用户资料快照的具体渲染或把所有网络/网关错误解释为会话失效。

当前实现范围是 `SparkClient` iOS 客户端；服务端 Refresh Token 的签发、轮换与失效规则不在本仓库内。

## 二、Token 刷新模块结构

### 结构职责表

| 层级 | 职责 | 关键代码 |
| --- | --- | --- |
| 登录 API | 将登录/验证码响应转换为 `AuthTokens` 并写入统一 Provider | `Projects/Core/Networking/API/Auth/AuthAPI.swift`、`OTPAPI.swift` |
| 令牌所有者 | 保存、读取、刷新与清理 Token；去重并发刷新 | `Projects/Core/Networking/AuthTokenProvider.swift` |
| 网络编排 | 在请求前注入 Authorization；401 后刷新并重试 | `Projects/Core/Networking/SparkNetworkEngine.swift` |
| 会话恢复 | 冷启动预热 Token，读取/清理 `UserSession` 快照 | `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift`、`SessionSnapshotStore.swift` |
| 全局退出 | 接收明确认证失效通知并将应用切至 `signedOut` | `Projects/Core/Networking/SparkNetworkModels.swift`、`Projects/App/Sources/App/Architecture/RouteCoordinator.swift`、`AppLifecycleCoordinator.swift` |
| 测试 | 覆盖刷新去重与 401 刷新失败通知 | `Tests/Networking/SparkNetworkEngineTests.swift`、`AuthSessionInvalidationTests.swift` |

### 具体目录结构

```text
SparkClient/
├── Projects/
│   ├── Core/Networking/
│   │   ├── AuthTokenProvider.swift
│   │   ├── SparkNetworkEngine.swift
│   │   ├── SparkNetworkModels.swift
│   │   ├── SerialRequestGate.swift
│   │   └── API/
│   │       ├── Auth/AuthAPI.swift
│   │       └── Auth/OTPAPI.swift
│   ├── Foundation/Utilities/JWTExpParser.swift
│   ├── Features/Auth/Infrastructure/
│   │   ├── DefaultAuthRepository.swift
│   │   └── SessionSnapshotStore.swift
│   └── App/Sources/App/
│       ├── AppSessionStore.swift
│       └── Architecture/
│           ├── RouteCoordinator.swift
│           └── AppLifecycleCoordinator.swift
└── Tests/Networking/
    ├── SparkNetworkEngineTests.swift
    └── AuthSessionInvalidationTests.swift
```

依赖方向为：业务 API/Operation → `SparkNetworkEngine` → `AuthTokenProvider`/Transport；全局认证失效由网络层发出 `NotificationCenter` 通知，再由 App 层协调器改变 UI 会话状态。`AuthTokenProvider` 是 `actor`，没有单独的 Domain 或 Repository 抽象层。

## 三、令牌写入、保存与预刷新

### 需求说明

登录、Apple 登录、设备登录和 OTP 验证成功后，客户端应把 Access Token、Refresh Token、过期时间和 Token 类型写入同一个 Provider。后续鉴权请求只能从该 Provider 获取 Authorization，避免模块各自保存 Token。

### 基础要求与业务规则

- Access Token 的到期时间在登录响应的 `expiresIn` 或刷新后 JWT 的 `exp` 中取得。
- `expiresAt` 前 30 秒开始刷新，避免请求恰好落在服务端过期边界。
- 未到刷新窗口时直接使用缓存/Keychain 中的 Access Token。
- 刷新暂时不可用时，保留本地令牌并让请求按原策略继续/失败；不得仅因网络、网关或不可解析响应强制退出。
- `AuthTokenProvider` 用单个 `refreshTask` 合并并发刷新，所有等待方共享结果。

### 验收标准

- [ ] 登录后 Keychain 中可恢复 `accessToken`、`refreshToken`、`expiresAt`、`tokenType`。
- [ ] 距 `expiresAt` 30 秒以内的任一鉴权请求先进行一次刷新。
- [ ] 同时触发多个刷新时，实际 Refresh HTTP 请求只发出一次。
- [ ] 刷新短暂失败不将 `AppSessionStore` 置为 `signedOut`。

### 技术细节与设计代码位置

`AuthAPI`、`OTPAPI` 在成功响应后创建 `AuthTokens` 并调用 `AuthTokenProvider.setTokens(_:)`。Provider 将完整令牌集写入 Keychain service `SparkClient.Auth`，可用性为 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。`validTokens()` 通过 `shouldRefresh(tokens:)` 判断 `Date() + 30s >= expiresAt`；`authorizationHeaderValue()` 返回 `"<tokenType> <accessToken>"`。

JWT 只解析 Payload 中的 `exp` 用于本地刷新时机，不在客户端验证签名；签名与令牌有效性仍由服务端决定。

## 四、鉴权请求、401 刷新与重试

### 需求说明

Access Token 可能因时钟边界、服务端撤销或本地过期时间不一致而被接口拒绝。已鉴权请求收到 401 时，应先强制刷新 Token，并使用新 Token 重试原请求，而不是直接登出。

### 基础要求与业务规则

- `NetworkStrategy.requiresAuth == true` 的请求在 Transport 前注入 Authorization。
- HTTP 401 且仍有重试额度时调用 `forceRefreshTokens()`；成功后进入下一次循环，原请求重新组装并发送。
- 刷新调用不带 Authorization，路径为 `/api/v1/auth/token/refresh/`，请求体同时携带 `refresh`、`refresh_token`、`device_id`、`bundle_id`。
- 请求队列按 `serialKey` 串行；刷新本身再由 Provider 的 `refreshTask` 跨调用去重。
- 403 明确不等同于会话失效，避免权限不足导致错误退出。

### 验收标准

- [ ] 受保护接口首次 401、刷新成功后，以新的 Authorization 重试并能返回业务结果。
- [ ] 重试后的 401 或其他最终 HTTP 错误按网络错误返回给业务调用方。
- [ ] 403 `permission_denied` 不触发退出。
- [ ] 同一时间多条 401 请求不会产生多次 Refresh 请求。

### 技术细节与设计代码位置

`SparkNetworkEngine.performAttempt(_:)` 在组装 `URLRequest` 时调用 `authorizationHeaderValue()`；`sendRaw(_:)` 的 401 分支执行强制刷新和循环重试。`SerialRequestGate` 负责同 `serialKey` 的顺序执行，`AuthTokenProvider.refreshTokensDeDuplicated()` 负责刷新任务去重。

## 五、明确失效、会话恢复与退出边界

### 需求说明

退出不是 Access Token 过期的默认结果。仅当本地没有刷新凭证，或服务端明确判定 Refresh Token/设备会话不可恢复时，才清除凭证并返回登录态。

### 基础要求与业务规则

- `missingTokens`：清除 Token，属于未登录状态。
- Refresh 响应包含业务码 `40100...40199`、`40300...40399`，或消息完全匹配 `token_not_valid`、`device_session_revoked`、`device_session_replaced`、`device_session_not_found`、`device_mismatch` 时，判为明确失效。
- 明确失效时 Provider 清空 Keychain，并发布 `AuthSessionInvalidation`。
- `AuthSessionInvalidation.shouldInvalidate` 将 401、明确 Token/设备会话失效消息和 401xx 业务码视为失效；403 一律不触发。
- `RouteCoordinator` 接收事件并交给 `AppLifecycleCoordinator`，后者将 `AppSessionStore` 切换到 `signedOut` 并清理账号运行时。
- 冷启动恢复时，`DefaultAuthRepository` 可在明确 Token 失败时清理 `SessionSnapshotStore`；刷新暂时不可用则保留本地 `UserSession` 快照。

### 验收标准

- [ ] Access Token 到期、刷新成功时应用继续保持 `signedIn`。
- [ ] 网络断开或刷新服务暂不可用时应用不强制回登录页。
- [ ] 服务端返回明确设备会话撤销/Token 无效信号时，Keychain Token、认证设备缓存与会话快照被清理，根视图回到登录态。
- [ ] 403 不退出；401 或明确认证失效事件才可退出。

### 技术细节与设计代码位置

失效判定在 `AuthTokenProvider.isDefinitiveRefreshAuthFailure(_:)` 和 `AuthSessionInvalidation.shouldInvalidate(statusCode:backendCode:message:)`。前者服务于 Refresh 接口；后者是所有网络/实时通道向 App 层发送退出事件的统一门槛。`DefaultAuthRepository.restoreSession()` 负责冷启动时 Token 与 `UserSession` 快照的协调。

## 六、整体业务流程

```text
登录/OTP 成功
  ↓
API 创建 AuthTokens → AuthTokenProvider.setTokens → Keychain
  ↓
已鉴权业务请求
  ↓
authorizationHeaderValue
  ├─ 未接近到期：注入当前 Access Token
  └─ 接近到期：Refresh Token 去重刷新
       ├─ 成功：保存新 Token 后发起请求
       ├─ 暂时失败：保留本地会话，不主动退出
       └─ 明确失效：清 Token → AuthSessionInvalidation → signedOut
  ↓
服务端响应
  ├─ 2xx：返回业务结果
  ├─ 401：强制刷新一次 → 原请求重试
  └─ 403/其他错误：按错误模型上抛，不以过期为由退出
```

### 成功路径

预刷新成功时，`performRefresh()` 从 JWT `exp` 更新 `expiresAt` 并写回 Keychain。401 触发的刷新成功后，`sendRaw(_:)` 重新执行 `performAttempt(_:)`，因此 Authorization 使用新 Access Token。

### 失败、重试和恢复

Refresh HTTP 非成功且未命中明确失效规则时，返回 `.refreshTemporarilyUnavailable`。`validTokens()` 对该错误回退旧 Access Token；冷启动也保留本地 Session 快照。网络层按各请求的 `RetryConfig` 处理可重试的传输/HTTP 错误。明确失效才执行 Token、设备认证缓存和会话快照清理。

### 取消、并发和幂等

取消请求会映射为 `SparkNetworkError.cancelled`。普通请求按 `serialKey` 排队；刷新过程跨请求去重。刷新 endpoint 的请求策略标记为非幂等，网络引擎不会将其作为普通幂等请求自动重放。

## 七、状态模型

| 状态 | 进入条件 | 用户可见结果 | 退出条件 |
| --- | --- | --- | --- |
| Token 可用 | 当前时间未进入 30 秒刷新窗口 | 已登录，正常请求 | 接近到期或收到 401 |
| 预刷新中 | Token 接近/达到 `expiresAt` | 通常无感 | 成功、暂时失败或明确失效 |
| 401 刷新重试 | 已鉴权请求收到 401 | 当前请求等待刷新后重试 | 重试成功或刷新失败 |
| 暂时不可用 | 刷新网络/服务失败，且非明确失效 | 保持登录态；当前业务请求可能提示失败 | 下次刷新成功或服务端明确失效 |
| 明确认证失效 | 缺 Refresh Token，或服务端明确撤销/无效 | 回到登录页 | 用户重新登录 |
| `AppSessionStore.signedOut` | 退出事件被 App 层处理 | 访客/登录界面 | 认证成功 |

## 八、数据与持久化

| 数据 | 所有者 | 存储位置 | 生命周期 | 清理时机 |
| --- | --- | --- | --- |
| Access Token | `AuthTokenProvider` | Keychain `SparkClient.Auth/accessToken` 与 actor 缓存 | 登录/刷新至明确失效 | 显式登出、缺 Token、明确刷新失效 |
| Refresh Token | `AuthTokenProvider` | Keychain `SparkClient.Auth/refreshToken` 与 actor 缓存 | 登录/刷新至明确失效 | 同上 |
| `expiresAt`、`tokenType` | `AuthTokenProvider` | Keychain | 与 Token 同生命周期 | 同上 |
| `UserSession` | `SessionSnapshotStore` | `UserDefaults`，键 `spark.session.current` | 登录快照/冷启动恢复 | 显式登出或冷启动确认失效 |
| 当前 UI 会话 | `AppSessionStore` | 内存 | App 运行期 | 收到退出、账号切换或进程结束 |

## 九、错误模型

| 错误类别 | 触发条件 | 是否重试 | 用户反馈 | 清理动作 |
| --- | --- | --- | --- |
| `refreshTemporarilyUnavailable` | 网络、网关、非明确鉴权 Refresh 错误 | 后续请求再次尝试；网络层可按策略重试 | 当前操作失败或稍后重试 | 保留 Token 与会话 |
| `refreshFailed` | Refresh 返回明确 Token/设备会话失效 | 不继续保活 | 登录状态已失效 | 清 Keychain 并发失效通知 |
| `missingTokens` | 缺失 Refresh Token | 不可刷新 | 要求登录 | 清残留 Token；由调用链进入未登录态 |
| `invalidRefreshResponse` | 2xx 刷新响应缺有效 Access Token 或 JWT `exp` 无法解析 | 不作为网络临时错误自动恢复 | 当前操作失败 | 常规请求保持会话；冷启动恢复会清理快照 |
| HTTP 401 | 受保护业务接口拒绝 | 强制刷新一次后重试 | 重试后仍失败才反馈 | 取决于刷新结果 |
| HTTP 403 | 权限不足 | 依请求策略 | 权限提示 | 不退出 |

## 十、与其他模块的接口边界

### 本模块负责

令牌保存、刷新、Authorization 注入、401 刷新重试、明确失效的通知和凭证清理。

### 本模块不负责

服务端 Refresh Token 签发策略、登录表单与 Apple/OTP 交互、业务接口权限规则、用户资料的展示，以及因普通网络故障把用户强制退出。

### 上游调用方

`SparkAuthAPI`、`SparkOTPAPI` 写入新 Token；所有 `requiresAuth` 的 `SparkNetworkRequest`、聊天实时连接、冷启动 `DefaultAuthRepository` 读取 Token；`ContentView` 启动 `RouteCoordinator` 的系统事件监听。

### 下游依赖

`SparkNetworkTransport` 发送 Refresh HTTP 请求；Keychain 持久化敏感令牌；`SparkSystemInfo` 提供设备/Bundle 标识；`NotificationCenter` 广播明确认证失效；App 生命周期协调器负责 UI 会话迁移。

### 输入和输出契约

输入为 `AuthTokens`、Refresh Token，以及后端 Refresh JSON（顶层 `access`/`refresh` 或 `access_token`/`refresh_token`）。输出为 Authorization header、新 `AuthTokens` 或 `AuthTokenProviderError`；全局失效通过 `AuthSessionInvalidation.notificationName` 发送 `statusCode`、`backendCode`、`message`、`source`。

## 十一、关键代码对应关系

| 能力 | 代码位置 | 当前职责 |
| --- | --- | --- |
| 登录后写 Token | `Projects/Core/Networking/API/Auth/AuthAPI.swift`、`OTPAPI.swift` | 登录、Apple/设备/OTP 成功后构建并写入 `AuthTokens` |
| Token 生命周期 | `Projects/Core/Networking/AuthTokenProvider.swift` | 30 秒预刷新、去重、Keychain、明确失效清理 |
| JWT 到期解析 | `Projects/Foundation/Utilities/JWTExpParser.swift` | 从刷新得到的 Access JWT 取 `exp` |
| 请求注入与 401 重试 | `Projects/Core/Networking/SparkNetworkEngine.swift` | 注入 Authorization、刷新重试和网络错误映射 |
| 请求调度 | `Projects/Core/Networking/SerialRequestGate.swift` | 依 `serialKey` 串行与优先级队列 |
| 冷启动与会话快照 | `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift`、`SessionSnapshotStore.swift` | Token 预热、会话快照恢复/清理 |
| 退出判定 | `Projects/Core/Networking/SparkNetworkModels.swift` | 401/明确认证失败过滤，403 排除 |
| App 退出执行 | `Projects/App/Sources/App/Architecture/RouteCoordinator.swift`、`AppLifecycleCoordinator.swift` | 接收通知并写入 `signedOut` |
| 自动化测试 | `Tests/Networking/SparkNetworkEngineTests.swift`、`AuthSessionInvalidationTests.swift` | 刷新去重、401 通知、403/消息判定 |

## 十二、测试策略

### 已有测试

- `SparkNetworkEngineTests` 覆盖多个请求共享一次刷新，以及 Refresh 返回 `40102/token_not_valid` 时发布认证失效通知。
- `AuthSessionInvalidationTests` 覆盖 401 应失效、403 不失效、`token_not_valid` 与设备会话被替换时应失效。

### 当前测试缺口

- 未找到“Access Token 已过期但 Refresh 成功后仍保持 `signedIn`”的 App/会话层测试。
- 未找到“刷新暂时不可用时保留 `AppSessionStore.signedIn`”的端到端测试。
- 未找到对 Keychain 持久化、重启后预刷新和清理顺序的集成测试。
- `SparkAuthAPI.refresh(refreshToken:)` 与 `AuthTokenProvider.performRefresh()` 都直接访问同一 Refresh endpoint；在当前项目代码搜索中未发现前者调用方，需在后续重构前确认是否保留。

### 建议补充测试

- Access 已过期、Refresh 成功：断言只刷新一次、原请求重试成功、`AppSessionStore` 不退出。
- Refresh 网络超时/5xx：断言 Token 与 SessionSnapshot 不被清理。
- 401 + 明确 Refresh Token 无效：断言 Keychain、SessionSnapshot、设备认证缓存被清理并进入 `signedOut`。
- 403：断言不发布 `AuthSessionInvalidation`。

## 十三、当前实现、缺口与演进

### 当前实现

- **当前实现**：采用短 Access Token + Refresh Token；Access Token 到期前 30 秒刷新，符合无感续期语义。
- **当前实现**：401 不直接退出，而是先强制刷新并重试原请求。
- **当前实现**：刷新失败默认保留登录态；只有明确认证失效才清理和退出。
- **当前实现**：退出事件已经接入根路由与生命周期协调器，并非仅网络层日志。

### 当前缺口

- **当前缺口**：没有覆盖“保活而不退出”完整 UI/会话链路的自动化测试。
- **当前缺口**：存在两个直接调用 `/api/v1/auth/token/refresh/` 的实现，其中 `SparkAuthAPI.refresh(refreshToken:)` 当前未找到调用方；其响应解析与 `AuthTokenProvider` 的兼容规则不同。

### 建议演进

- **建议演进**：若确认 `SparkAuthAPI.refresh(refreshToken:)` 无调用方，将其收敛到 `AuthTokenProvider` 或删除，确保 Refresh 响应兼容、失效判定和并发去重只有一个事实源。
- **建议演进**：补充上述会话层测试，但保持“Access Token 到期和临时刷新失败不退出”的产品语义不变。

## 十四、整体验收标准

- [ ] Access Token 自然到期时，客户端优先刷新而非登出。
- [ ] Refresh 成功后，后续请求使用新 Token，用户保持登录。
- [ ] 401 先刷新后重试；403 不触发退出。
- [ ] 网络、网关和非明确认证错误不清除本地会话。
- [ ] 仅缺失 Refresh Token 或服务端明确判定 Token/设备会话失效时，才清理凭证并回登录页。
- [ ] Token、会话快照、App UI 状态的所有者和清理责任可分别追溯到真实代码。
- [ ] 关键代码路径与现有测试文件均可定位。
