# CHAT-000033 对话引导卡片去同步选择成员后 HealthKit 授权页无法打开排查工单

## 背景

在对话引导卡片健康数据滑块中，用户点击「去同步」后进入设备同步页面，选择成员后无法正常打开 HealthKit 授权页面。

用户提供的关键日志：

```text
Attempt to present <HKHealthPrivacyHostAuthorizationViewController ...>
on <_TtGC7SwiftUI29PresentationHostingControllerVS_7AnyView_: ...>
whose view is not in the window hierarchy.
```

本工单只做排查分析与解决方案，不改动现有代码。

## 当前日志判断

当前日志已经能够体现问题，不需要先增加临时日志。

日志说明：

- HealthKit 授权控制器已经被系统创建：`HKHealthPrivacyHostAuthorizationViewController`。
- 系统准备 present 授权页时失败。
- 失败原因不是 HealthKit capability、权限声明或 readTypes 缺失，而是 present 的宿主视图控制器不在当前 window 层级中。

也就是说，请求已经走到 HealthKit 授权展示阶段，但调用时机不对。

## 功能详细排查

### 入口链路

对话引导卡片健康滑块未授权时展示「去绑定 / 去同步」动作。

当前链路：

```text
ChatGuideActionButton
  ↓ NotificationCenter.post(.chatGuideBindHealthRequested)
ChatView.onReceive(.chatGuideBindHealthRequested)
  ↓ isShowingGuideAddDevice = true
ChatGuideAddDeviceSheet
  ↓ AddDeviceView(viewModel: DeviceBindingUseCase)
AddDeviceView 点击苹果健康「去同步」
  ↓ pickMemberForAppleHealth = true
MemberSelectionSheet 选择成员
  ↓ pickMemberForAppleHealth = false
  ↓ bindAppleHealth(to: member)
DeviceBindingUseCase.bindAppleHealth
  ↓ HealthKitAuthorizationStore.requestAuthorization()
HKHealthStore.requestAuthorization(...)
```

### 高概率根因

`AddDeviceView` 在 `MemberSelectionSheet` 的选择回调里同步做了两件事：

```swift
pickMemberForAppleHealth = false
bindAppleHealth(to: member)
```

这会导致：

1. 成员选择 sheet 正在 dismiss。
2. `AddDeviceView` 所在的 SwiftUI presentation hosting controller 处于切换或即将离开 window hierarchy 的状态。
3. `HKHealthStore.requestAuthorization` 立即请求系统展示 HealthKit 授权页。
4. 系统尝试从一个不稳定或不在 window hierarchy 的 controller 上 present。
5. 授权页无法打开，并输出 `whose view is not in the window hierarchy`。

因此问题核心不是“没调用 HealthKit 授权”，而是“调用 HealthKit 授权时，当前 SwiftUI sheet 层级还没完成 dismiss / 宿主 controller 不可用”。

## 解决方案

### 方案 A：延迟到成员选择 sheet 完全关闭后再请求授权

推荐方案。

改造 `AddDeviceView`：

- 新增 `@State private var pendingAppleHealthMember: Member?`。
- 成员选择回调里只记录待绑定成员，并关闭成员选择 sheet。
- 在 `pickMemberForAppleHealth` 变为 `false` 后，再异步触发 `bindAppleHealth`。
- 触发前至少等待一个 MainActor turn，确保 SwiftUI presentation 完成。

目标流程：

```text
选择成员
  ↓
记录 pendingAppleHealthMember
  ↓
关闭 MemberSelectionSheet
  ↓
AddDeviceView 回到稳定 window hierarchy
  ↓
再调用 HKHealthStore.requestAuthorization
```

示例方向：

```swift
MemberSelectionSheet(...) { member in
    pendingAppleHealthMember = member
    pickMemberForAppleHealth = false
}
.onChange(of: pickMemberForAppleHealth) { isPresented in
    guard isPresented == false, let member = pendingAppleHealthMember else { return }
    pendingAppleHealthMember = nil
    Task { @MainActor in
        await Task.yield()
        bindAppleHealth(to: member)
    }
}
```

### 方案 B：把授权动作提升到 AddDevice sheet 的稳定宿主层

如果方案 A 在真机仍偶发失败，可以将绑定动作从 `MemberSelectionSheet` 回调提升到 `ChatGuideAddDeviceSheet` 或更外层协调器。

目标：

- 子 sheet 只负责选择成员。
- 顶层 AddDevice sheet 完全可见后，再执行 HealthKit 授权。
- 避免在嵌套 sheet dismiss 过程中请求系统隐私授权页。

适用场景：

- iOS 26 / SwiftUI sheet 层级在真机上仍存在 presentation race。
- 对话页内还有其他 sheet、全屏 cover 或 tool preview presentation 并发。

### 方案 C：先关闭设备绑定 sheet，再从 ChatView 顶层触发授权

这是最稳但交互变化最大的方案。

流程：

```text
选择成员
  ↓
关闭 MemberSelectionSheet
  ↓
关闭 ChatGuideAddDeviceSheet
  ↓
ChatView 顶层确认当前 view 在 window 中
  ↓
调用 HealthKit 授权
  ↓
授权完成后重新打开或刷新绑定状态
```

优点：

- HealthKit 授权页从更稳定的页面层级发起。

缺点：

- 用户会看到设备绑定 sheet 关闭，体验比方案 A 多一次跳转感。
- 需要新增父子通信状态，改动面更大。

## 推荐落地

第一阶段采用方案 A。

原因：

- 改动最小。
- 不改变现有交互层级。
- 直接针对日志中的 `view is not in the window hierarchy`。
- 不影响对话引导卡片健康滑块的实时读取逻辑。
- 不影响科普问题生成流程。

若方案 A 后仍偶发失败，再升级方案 B。

## 验收标准

1. 从对话引导卡片点击「去同步」能打开设备同步页面。
2. 选择成员后 HealthKit 授权页稳定弹出。
3. Xcode 控制台不再出现：

```text
Attempt to present <HKHealthPrivacyHostAuthorizationViewController ...>
whose view is not in the window hierarchy.
```

4. 授权完成后设备绑定记录写入本地。
5. 返回对话页后健康数据滑块能刷新为授权后的实时状态。
6. 科普问题生成、点击发送流程不受影响。

## 涉及文件

- `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/Guide/ChatGuideMetricCarouselView.swift`
- `SparkClient/Projects/Features/Chat/Presentation/ChatView.swift`
- `SparkClient/Projects/Features/DeviceBinding/Presentation/AddDeviceView.swift`
- `SparkClient/Projects/Features/DeviceBinding/Application/DeviceBindingUseCase.swift`
- `SparkClient/Projects/Features/DeviceBinding/Infrastructure/HealthKitAuthorizationStore.swift`

## 风险与注意事项

- 不要在嵌套 SwiftUI sheet 的 dismiss 回调内立即请求系统隐私授权页。
- 不要为了规避问题而提前触发 HealthKit 授权，否则会破坏“未绑定不弹授权”的流程要求。
- 不要把 HealthKit 授权放到引导卡片渲染阶段，授权只能来自用户明确点击「去同步」后的主动动作。
- 如果未来同一页面还有相册、相机、通知等系统授权，也应遵循同样原则：先关闭内部选择弹层，再从稳定可见宿主触发系统授权。
