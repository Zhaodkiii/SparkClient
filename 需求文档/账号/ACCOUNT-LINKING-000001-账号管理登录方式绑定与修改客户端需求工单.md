# ACCOUNT-LINKING-000001 账号管理登录方式绑定与修改客户端需求工单

创建日期：2026-07-15  
关联模块：账号管理页、登录方式管理、手机号 OTP、邮箱 OTP、Apple 登录、账号安全验证  
优先级：P0  
需求类型：客户端账号管理 / 登录方式绑定 / 登录方式修改

## 1. 背景

当前账号管理页已有账号信息展示与注销前安全认证能力：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift:63-98
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift:69-143
```

现需要扩展账号管理页，支持展示邮箱、手机号、Apple 三种登录方式，并提供绑定和修改流程。

用户操作必须遵循安全流程：

```text
先使用已绑定的认证方式完成安全认证
认证通过后进入目标登录方式绑定或修改页面
目标手机号/邮箱/Apple 验证通过后提交服务端登记
服务端写入或更新 SocialIdentity
```

## 2. 目标

1. 账号管理页展示邮箱、手机号、Apple 登录方式的绑定状态。
2. 未绑定方式展示“绑定”入口。
3. 已绑定手机号、邮箱展示“修改”入口。
4. Apple 已绑定时只展示状态，不提供修改入口；未绑定时支持绑定。
5. 绑定或修改前必须先完成已有登录方式认证。
6. 目标方式验证通过后调用服务端绑定或修改接口。
7. 服务端返回“已绑定其他用户”时，客户端明确提示用户不能继续。

## 3. 非目标

1. 本工单不调整登录页主登录流程。
2. 本工单不实现账号合并。
3. 本工单不支持 Apple ID 修改。
4. 本工单不允许用户解绑最后一种登录方式。
5. 本工单不处理客服申诉流程，只展示服务端错误提示。

## 4. 当前客户端状态

### 4.1 当前账号信息展示

`AccountManagementView.accountInfoSection` 当前展示：

1. account_id
2. 当前 contact
3. signInMethod
4. signInTime

不足：

1. 只能展示当前登录方式。
2. 不能展示多登录方式绑定状态。
3. 没有绑定/修改入口。

### 4.2 当前安全认证组件

`VerificationMethodCard` 已支持选择：

```text
apple
phone
email
```

这部分可以复用为绑定/修改流程的第一步。

### 4.3 当前 ViewModel

`AccountManagementViewModel.availableVerificationChannels` 当前基于 `profile.signInMethod` 推断可认证方式。

绑定/修改后，需要改为基于服务端返回的 `identities` 列表生成可认证方式，而不是只看当前登录方式。

## 5. 页面设计

### 5.1 登录方式区块

在账号管理页新增区块：

```text
登录方式
```

每一行展示：

| 字段 | 说明 |
|---|---|
| 图标 | 手机号、邮箱、Apple |
| 标题 | 手机号、邮箱、Apple |
| 状态 | 已绑定时展示掩码值；未绑定时展示“未绑定” |
| 操作 | 未绑定展示“绑定”；手机号/邮箱已绑定展示“修改”；Apple 已绑定无修改入口 |

建议展示：

| 登录方式 | 未绑定 | 已绑定 |
|---|---|---|
| 手机号 | 绑定 | `+86138****00` + 修改 |
| 邮箱 | 绑定 | `ab***c@example.com` + 修改 |
| Apple | 绑定 | Apple ID 已绑定 |

### 5.2 操作入口规则

| 状态 | 手机号 | 邮箱 | Apple |
|---|---|---|---|
| 未绑定 | 显示绑定 | 显示绑定 | 显示绑定 |
| 已绑定 | 显示修改 | 显示修改 | 不显示修改 |
| 当前账号只有一种登录方式 | 允许绑定新方式 | 允许绑定新方式 | 允许绑定 Apple |

客户端不自行判断目标是否已被其他用户绑定，最终以服务端结果为准。

### 5.3 Apple 登录响应邮箱展示规则

Apple 登录响应中可能包含 `email` 字段，但客户端不能把它理解为“邮箱登录方式已绑定”。

规则：

1. 账号管理页邮箱绑定状态必须来自 `GET /api/v1/accounts/identities/` 的 `provider=email` 状态。
2. Apple 登录响应中的 `email` 只能作为当前账号展示邮箱使用，且以服务端返回值为准。
3. 如果用户原本已有账号邮箱，服务端不会因为 Apple token 携带新 email 而覆盖；客户端不做本地覆盖。
4. Apple 登录成功后，如需刷新账号管理页，必须重新拉取登录方式列表或账号 profile。
5. Apple ID 已绑定不等于邮箱已绑定；邮箱仍需走邮箱绑定流程。

## 6. 绑定流程

### 6.1 流程总览

```text
用户点击“绑定手机号/邮箱/Apple”
-> 选择并完成已有方式安全认证
-> 服务端返回 verification_ticket
-> 进入目标方式验证页面
-> 目标方式验证通过
-> 调用绑定接口
-> 刷新账号登录方式列表
```

### 6.2 第一步：已有方式认证

客户端展示 `VerificationMethodCard`，认证方式来自服务端返回的已绑定 identities。

规则：

1. 如果已有手机号，允许短信 OTP 认证。
2. 如果已有邮箱，允许邮箱 OTP 认证。
3. 如果已有 Apple，允许 Apple 再认证。
4. 如果当前用户没有任何可认证方式，不能进入绑定流程，展示错误。

认证完成后，客户端保存：

```text
verification_ticket
```

该 ticket 只用于当前绑定流程。

### 6.3 第二步：目标方式验证

按目标方式进入不同页面：

| 目标方式 | 页面内容 |
|---|---|
| 手机号 | 手机号输入、发送验证码、验证码输入 |
| 邮箱 | 邮箱输入、发送验证码、验证码输入 |
| Apple | Sign in with Apple 按钮 |

目标验证通过后，客户端调用：

```text
POST /api/v1/accounts/identities/bind/
```

### 6.4 绑定成功

成功后：

1. 关闭流程弹层。
2. 清空本地验证码、ticket、输入值。
3. 调用登录方式列表接口刷新数据。
4. 如服务端返回新的 `UserSession` 或 profile，更新本地 session 快照。
5. 展示成功提示。

## 7. 修改流程

### 7.1 支持范围

本期只支持：

```text
手机号修改
邮箱修改
```

不支持：

```text
Apple 修改
```

### 7.2 流程总览

```text
用户点击“修改手机号/邮箱”
-> 先选择并验证已有方式
-> 服务端返回 verification_ticket
-> 进入新手机号/新邮箱输入页面
-> 发送并验证新目标 OTP
-> 调用修改接口
-> 刷新账号登录方式列表
```

### 7.3 旧方式认证

旧方式认证不一定必须使用“正在修改的方式”。用户可以使用任一已绑定方式完成安全认证。

例：

1. 修改手机号时，可以先用 Apple 认证。
2. 修改邮箱时，可以先用手机号 OTP 认证。
3. 如果服务端要求必须验证原手机号/原邮箱，则客户端按服务端返回的 `allowed_verification_providers` 展示。

默认推荐：允许任一已绑定方式认证，提高可用性。

### 7.4 新方式验证

新手机号或新邮箱必须完成 OTP 验证。

修改接口：

```text
POST /api/v1/accounts/identities/change/
```

成功后刷新列表。

## 8. 状态机建议

当前 `AccountDeactivationFlowState` 是注销专用。建议新增账号身份管理专用状态，不继续复用注销状态名。

建议：

```swift
enum AccountIdentityFlowState: Equatable {
    case idle
    case choosingReauth(operation: AccountIdentityOperation)
    case reauthOTP(operation: AccountIdentityOperation, channel: AccountVerificationChannel, otpID: String)
    case reauthApple(operation: AccountIdentityOperation)
    case enteringTarget(operation: AccountIdentityOperation, ticket: String)
    case targetOTP(operation: AccountIdentityOperation, ticket: String, otpID: String)
    case submitting
    case completed
    case failed(String)
}
```

操作类型：

```swift
enum AccountIdentityOperation: Equatable {
    case bind(provider: AccountIdentityProvider)
    case change(provider: AccountIdentityProvider)
}
```

登录方式模型：

```swift
enum AccountIdentityProvider: String, Equatable, Sendable {
    case phone
    case email
    case apple
}
```

## 9. 数据模型建议

服务端返回的登录方式列表映射为：

```swift
struct AccountIdentityStatus: Equatable, Sendable {
    let provider: AccountIdentityProvider
    let bound: Bool
    let maskedValue: String
    let modifiable: Bool
    let bindable: Bool
}
```

账号 profile 建议扩展：

```swift
struct AccountProfile {
    ...
    let identities: [AccountIdentityStatus]
}
```

如果服务端将登录方式列表做成独立接口，客户端也可以将它作为单独 ViewModel 状态维护。

## 10. 接口依赖

客户端依赖服务端提供：

| 接口 | 用途 |
|---|---|
| `GET /api/v1/accounts/identities/` | 获取登录方式状态 |
| `POST /api/v1/accounts/identity-verification/request/` | 请求已有方式再认证 |
| `POST /api/v1/accounts/identity-verification/verify/` | 完成再认证，获取 ticket |
| `POST /api/v1/accounts/identities/bind/` | 绑定新登录方式 |
| `POST /api/v1/accounts/identities/change/` | 修改手机号或邮箱 |

客户端需要继续传：

```text
bundle_id
device_id
```

## 11. 错误处理

| 服务端 msg | 客户端提示 |
|---|---|
| `identity_already_bound_to_active_user` | 该登录方式已绑定其他账号，无法绑定或修改 |
| `verification_ticket_expired` | 验证已过期，请重新验证 |
| `verification_ticket_used` | 验证已失效，请重新验证 |
| `target_otp_invalid` | 验证码错误，请重新输入 |
| `target_otp_expired` | 验证码已过期，请重新获取 |
| `apple_identity_change_not_supported` | Apple 登录暂不支持修改 |
| `last_identity_cannot_be_removed` | 请至少保留一种可用登录方式 |

客户端不展示服务端原始手机号、邮箱或 Apple `sub`。
客户端不使用 Apple credential payload 中的邮箱直接改写本地账号邮箱。

## 12. 安全与体验细节

1. 弹层关闭时必须清理 OTP、ticket、目标输入。
2. 切换目标登录方式时必须清空上一次 OTP。
3. ticket 过期后必须回到第一步安全认证。
4. 发送验证码按钮需要倒计时。
5. 绑定或修改提交中禁用按钮，防止重复提交。
6. 进入后台再回来时，如果 ticket 已经过期，提示重新认证。
7. 服务端返回冲突时，保留当前页面，允许用户更换目标手机号或邮箱。
8. Apple 授权取消时，不算失败，只返回上一层。

## 13. 需求分歧与待确认

### 13.1 邮箱是否纳入 SocialIdentity

客户端需要展示邮箱为独立登录方式。服务端当前邮箱登录可能只依赖 `auth_user.email`。

可选方案：

| 方案 | 内容 | 客户端影响 |
|---|---|---|
| A，推荐 | 服务端新增 `email` provider，邮箱作为 SocialIdentity | 客户端模型统一，展示和修改规则清晰 |
| B | 邮箱继续只来自 `auth_user.email` | 客户端需要对邮箱做特殊分支 |
| C | 本期不支持邮箱绑定/修改 | 与当前需求不一致 |

### 13.2 修改手机号/邮箱时是否必须验证旧同类方式

可选方案：

| 方案 | 内容 | 建议 |
|---|---|---|
| A，推荐 | 任一已绑定方式认证通过即可修改 | 可用性好，符合“已有认证方式”描述 |
| B | 修改手机号必须先验证旧手机号，修改邮箱必须先验证旧邮箱 | 安全感更强，但旧手机号/邮箱不可用时无法修改 |
| C | 高风险账号要求验证两种方式 | 复杂度高，后续风控再做 |

### 13.3 Apple 是否允许解绑

可选方案：

| 方案 | 内容 | 建议 |
|---|---|---|
| A，推荐 | 本期 Apple 只支持绑定，不支持修改或解绑 | 范围清晰 |
| B | 支持解绑 Apple，但必须已有手机号或邮箱 | 可做二期 |
| C | 支持更换 Apple | 不建议本期做 |

## 14. 验收标准

1. 账号管理页展示手机号、邮箱、Apple 三种登录方式。
2. 未绑定方式展示绑定入口。
3. 已绑定手机号、邮箱展示修改入口。
4. 已绑定 Apple 不展示修改入口。
5. 点击绑定或修改后，必须先完成已有方式安全认证。
6. 安全认证通过后，进入目标方式验证页面。
7. 目标验证通过后，客户端调用服务端绑定或修改接口。
8. 绑定或修改成功后，账号管理页刷新并展示最新状态。
9. 目标已绑定其他 active 用户时，客户端展示明确错误。
10. 取消流程、验证码错误、ticket 过期、Apple 授权取消都有可恢复路径。
11. Apple 登录返回 email 时，账号管理页邮箱绑定状态仍以登录方式列表接口为准，不误显示为邮箱已绑定。
12. 用户已有邮箱时，Apple 登录返回不同 email 后，客户端不在本地覆盖已有邮箱展示。

## 15. 建议拆分任务

| 任务 | 负责人 | 说明 |
|---|---|---|
| 登录方式列表 UI | iOS | 在账号管理页新增三类登录方式展示 |
| 身份管理状态机 | iOS | 新增绑定/修改专用 flow state |
| 再认证流程接入 | iOS | 复用手机号、邮箱、Apple 认证组件 |
| 目标方式绑定页面 | iOS | 手机号、邮箱、Apple 三类目标验证 |
| 修改手机号/邮箱页面 | iOS | 新目标输入、OTP、提交 |
| 接口 Repository / UseCase | iOS | 对接 identities、verification、bind、change |
| 本地化错误提示 | iOS | 覆盖冲突、过期、验证码错误 |
| 联调测试 | iOS + 后端 | 覆盖绑定、修改、冲突、注销用户释放 |
