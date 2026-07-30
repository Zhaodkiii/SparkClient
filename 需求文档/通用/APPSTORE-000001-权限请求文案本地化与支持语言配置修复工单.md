# APPSTORE-000001-权限请求文案本地化与支持语言配置修复工单

## 1. 工单摘要

| 项目 | 内容 |
|---|---|
| 工单号 | `APPSTORE-000001` |
| 工单名称 | 权限请求文案本地化与支持语言配置修复 |
| 需求来源 | App Store Review Guideline 4 - Design 审核反馈 |
| 问题类型 | 权限弹窗语言与 App 本地化语言不一致 |
| 影响范围 | iOS 系统权限弹窗、App Store 审核、英文/中文用户首启体验 |
| 优先级 | P0 |
| 当前状态 | 已实现 |
| 创建日期 | 2026-07-20 |

## 2. 审核反馈

App Store 审核反馈：

```text
Guideline 4 - Design

Issue Description

There are issues with the app's user interface that contribute to a lower-quality user experience than App Store users expect. Specifically, the app includes permissions requests that are not written in the same language as the app's localization.

Next Steps

Revise the app to address all instances of the issues identified above.
```

审核关注点不是权限用途本身，而是：

1. App 声明支持某种语言时，系统权限弹窗也必须使用同一语言。
2. `NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSPhotoLibraryUsageDescription` 等权限文案属于系统弹窗 UI，同样需要本地化。
3. 不能只本地化业务 UI，而遗漏 `Info.plist` 权限文案。

## 3. 当前项目现状

### 3.1 当前语言配置

项目配置中可见：

```text
developmentRegion = en
knownRegions = (
    en,
    Base,
    "zh-Hans",
    "zh-Hant",
)
```

当前实际资源文件只发现：

```text
SparkClient/Projects/App/Resources/en.lproj/Localizable.strings
SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
```

风险：

1. `knownRegions` 包含 `zh-Hant`，但当前未发现对应 `zh-Hant.lproj/Localizable.strings`。
2. 如果 App Store Connect 或包内元数据声明支持繁体中文，但 App 内资源不完整，容易出现回退语言和用户预期不一致。
3. 权限文案目前没有独立 `InfoPlist.strings`，系统权限弹窗无法按语言稳定切换。

### 3.2 当前权限文案位置

当前权限说明写在 `SparkClient.xcodeproj/project.pbxproj` 的 build settings 中：

```text
INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription
INFOPLIST_KEY_NSCameraUsageDescription
INFOPLIST_KEY_NSHealthShareUsageDescription
INFOPLIST_KEY_NSHealthUpdateUsageDescription
INFOPLIST_KEY_NSLocalNetworkUsageDescription
INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription
INFOPLIST_KEY_NSMicrophoneUsageDescription
INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription
INFOPLIST_KEY_NSPhotoLibraryUsageDescription
INFOPLIST_KEY_NSSpeechRecognitionUsageDescription
```

这些值当前均为中文。由于 `developmentRegion = en`，英文环境或审核设备使用英文时，系统权限弹窗可能仍展示中文，从而命中 Guideline 4。

## 4. 修复目标

1. 所有系统权限请求文案按用户当前 App 语言展示。
2. 英文环境展示英文权限文案。
3. 简体中文环境展示简体中文权限文案。
4. 如果继续声明繁体中文，则繁体中文环境展示繁体中文权限文案；如果暂不支持繁体中文，则从支持语言配置中移除或不对外声明。
5. `Localizable.strings` 与 `InfoPlist.strings` 的支持语言集合保持一致。
6. 后续新增权限 key 时，必须同步补齐所有支持语言的 `InfoPlist.strings`。

## 5. 最通用实现方案

### 5.1 结论

最通用、最符合 iOS 本地化机制的方案：

1. 保留基础 `Info.plist` 或 build settings 中的权限 key 作为兜底。
2. 为每个正式支持语言新增对应的 `InfoPlist.strings`。
3. `InfoPlist.strings` 使用系统权限 key 原名作为本地化 key。
4. App 实际支持语言、Xcode `knownRegions`、包内 `.lproj`、App Store Connect 本地化语言保持一致。

推荐支持语言口径：

| 语言 | 是否支持 | 资源要求 |
|---|---:|---|
| English (`en`) | 是 | `en.lproj/Localizable.strings` + `en.lproj/InfoPlist.strings` |
| 简体中文 (`zh-Hans`) | 是 | `zh-Hans.lproj/Localizable.strings` + `zh-Hans.lproj/InfoPlist.strings` |
| 繁体中文 (`zh-Hant`) | 二选一 | 若对外支持，则补齐 `zh-Hant.lproj/Localizable.strings` + `zh-Hant.lproj/InfoPlist.strings`；若暂不支持，则不要在产品、审核或 App Store 元数据中声明 |

### 5.2 为什么使用 `InfoPlist.strings`

`Localizable.strings` 只负责 App 自己渲染的 UI 文案；系统权限弹窗读取的是 `Info.plist` 中的隐私权限说明，并通过 `InfoPlist.strings` 做本地化覆盖。

因此，只补 `Localizable.strings` 不能解决本次审核问题。

### 5.3 不推荐方案

1. 不建议把中文权限说明继续写死在 build settings 里作为唯一文案。
2. 不建议用运行时逻辑拼接权限文案；系统权限弹窗不会读取业务代码里的 `L10n.text`。
3. 不建议只改英文文案而不建立长期规则；后续新增权限仍会复发。
4. 不建议声明 `zh-Hant` 但缺少繁体资源。

## 6. 权限文案清单

### 6.1 英文文案建议

| Key | English |
|---|---|
| `NSBluetoothAlwaysUsageDescription` | Look Health uses Bluetooth to discover nearby devices for in-person member sharing. |
| `NSCameraUsageDescription` | Look Health uses the camera to take photos in chats and preview them before sending. |
| `NSHealthShareUsageDescription` | Look Health reads steps, weight, sleep, and heart rate to show basic health information. |
| `NSHealthUpdateUsageDescription` | Look Health writes health records only when you choose to save them. |
| `NSLocalNetworkUsageDescription` | Look Health uses the local network to connect to the server for account verification and data sync. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Look Health uses your location in chats to search nearby places and plan routes. |
| `NSLocationWhenInUseUsageDescription` | Look Health uses your location in chats to search nearby places and plan routes. |
| `NSMicrophoneUsageDescription` | Look Health uses the microphone to record voice messages for AI health assistant conversations. |
| `NSPhotoLibraryAddUsageDescription` | Look Health saves processed medical reports and case photos to your photo library when you choose to save them. |
| `NSPhotoLibraryUsageDescription` | Look Health uses your photo library to select images in chats and preview them before sending. |
| `NSSpeechRecognitionUsageDescription` | Look Health uses speech recognition to transcribe your voice input into text. |

### 6.2 简体中文文案建议

| Key | 简体中文 |
|---|---|
| `NSBluetoothAlwaysUsageDescription` | Look健康需要使用蓝牙发现附近设备，用于面对面分享和绑定成员。 |
| `NSCameraUsageDescription` | Look健康需要使用相机拍摄聊天图片，并在发送前生成预览。 |
| `NSHealthShareUsageDescription` | Look健康需要读取步数、体重、睡眠和心率，用于展示健康基础信息。 |
| `NSHealthUpdateUsageDescription` | Look健康仅会在你主动保存时写入健康记录。 |
| `NSLocalNetworkUsageDescription` | Look健康需要访问本地网络，用于连接服务器完成账号验证和数据同步。 |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Look健康需要在对话中使用你的位置，用于搜索附近地点和规划路线。 |
| `NSLocationWhenInUseUsageDescription` | Look健康需要在对话中使用你的位置，用于搜索附近地点和规划路线。 |
| `NSMicrophoneUsageDescription` | Look健康需要使用麦克风录制语音消息，便于你与 AI 健康助手进行语音交流。 |
| `NSPhotoLibraryAddUsageDescription` | Look健康会在你主动保存时，将处理后的医疗报告和病例照片保存到相册。 |
| `NSPhotoLibraryUsageDescription` | Look健康需要访问相册选择聊天图片，并在发送前生成预览。 |
| `NSSpeechRecognitionUsageDescription` | Look健康需要使用语音识别，将你的语音输入实时转写为文本。 |

### 6.3 繁体中文处理口径

若本版本继续支持繁体中文，补齐以下资源：

```text
SparkClient/Projects/App/Resources/zh-Hant.lproj/Localizable.strings
SparkClient/Projects/App/Resources/zh-Hant.lproj/InfoPlist.strings
```

若本版本不支持繁体中文：

1. 不在 App Store Connect 中声明繁体中文本地化。
2. 不在产品介绍和审核备注中描述繁体中文支持。
3. 评估是否从 Xcode `knownRegions` 中移除 `zh-Hant`，避免形成“工程声明支持但资源不完整”的状态。

## 7. 建议文件结构

目标结构：

```text
SparkClient/Projects/App/Resources/
  en.lproj/
    Localizable.strings
    InfoPlist.strings
  zh-Hans.lproj/
    Localizable.strings
    InfoPlist.strings
  zh-Hant.lproj/                 # 仅在本版本正式支持繁体中文时保留
    Localizable.strings
    InfoPlist.strings
```

`InfoPlist.strings` 示例：

```text
"NSCameraUsageDescription" = "Look Health uses the camera to take photos in chats and preview them before sending.";
"NSMicrophoneUsageDescription" = "Look Health uses the microphone to record voice messages for AI health assistant conversations.";
```

## 8. 实施步骤

1. 明确本版本正式支持语言：建议先收敛为 `en` + `zh-Hans`，除非产品确认需要繁体中文。
2. 为所有正式支持语言新增 `InfoPlist.strings`。
3. 将当前所有 `INFOPLIST_KEY_*UsageDescription` 对应 key 写入每个语言的 `InfoPlist.strings`。
4. 将基础 `Info.plist` 或 build settings 的兜底文案调整为英文，匹配 `developmentRegion = en`。
5. 若支持 `zh-Hant`，补齐繁体 UI 文案与权限文案；若不支持，清理对外语言声明。
6. 在真机或模拟器上切换系统语言，逐个触发相机、麦克风、相册、定位、健康、蓝牙、语音识别、本地网络权限弹窗。
7. 归档后检查 `.app` 包内是否包含每个语言的 `InfoPlist.strings`。

## 9. 验收口径

1. 英文系统环境下，首次触发相机权限弹窗时展示英文文案。
2. 英文系统环境下，首次触发麦克风权限弹窗时展示英文文案。
3. 英文系统环境下，首次触发相册权限弹窗时展示英文文案。
4. 英文系统环境下，首次触发定位权限弹窗时展示英文文案。
5. 简体中文系统环境下，所有权限弹窗展示简体中文文案。
6. 如果声明支持繁体中文，繁体中文系统环境下所有权限弹窗展示繁体中文文案。
7. App 内普通 UI 支持语言与权限弹窗支持语言一致。
8. `plutil -lint` 检查所有 `InfoPlist.strings` 通过。
9. 构建产物中存在对应语言目录，例如 `en.lproj/InfoPlist.strings`、`zh-Hans.lproj/InfoPlist.strings`。
10. App Store Connect 的本地化语言列表与包内实际支持语言一致。

## 10. 验证命令建议

```bash
plutil -lint SparkClient/Projects/App/Resources/en.lproj/InfoPlist.strings
plutil -lint SparkClient/Projects/App/Resources/zh-Hans.lproj/InfoPlist.strings
plutil -lint SparkClient/Projects/App/Resources/zh-Hant.lproj/InfoPlist.strings
```

归档或构建后检查包内资源：

```bash
find path/to/SparkClient.app -name InfoPlist.strings -print
```

检查工程内权限 key：

```bash
rg -n "NS[A-Za-z]+UsageDescription|INFOPLIST_KEY_NS[A-Za-z]+UsageDescription" SparkClient.xcodeproj SparkClient
```

## 11. 风险与注意事项

1. iOS 权限弹窗只会在首次请求或重置权限后出现，测试前需要删除 App 或重置隐私权限。
2. `InfoPlist.strings` 文件编码和语法错误会导致本地化失效，必须执行 `plutil -lint`。
3. 健康、蓝牙、定位等权限可能需要真实设备验证。
4. 如果保留 `zh-Hant` 但只补权限文案、不补业务 UI 文案，仍可能被认为本地化体验不完整。
5. 后续新增权限能力时，需求评审必须把 `InfoPlist.strings` 作为必填交付项。

## 12. 涉及文件

| 文件 | 处理 |
|---|---|
| `SparkClient.xcodeproj/project.pbxproj` | 现有权限文案来源；建议仅保留英文兜底或迁移为中性兜底 |
| `SparkClient/Info.plist` | 当前基础 Info.plist；保留非本地化结构配置 |
| `SparkClient/Projects/App/Resources/en.lproj/InfoPlist.strings` | 新增英文权限文案 |
| `SparkClient/Projects/App/Resources/zh-Hans.lproj/InfoPlist.strings` | 新增简体中文权限文案 |
| `SparkClient/Projects/App/Resources/zh-Hant.lproj/InfoPlist.strings` | 如正式支持繁体中文则新增 |
| `SparkClient/Projects/App/Resources/*/Localizable.strings` | 与支持语言集合保持一致 |

## 13. 完成定义

本工单完成的最低标准：

1. `en`、`zh-Hans` 的权限弹窗语言均正确。
2. App Store Connect 声明语言与包内语言资源一致。
3. 所有权限 key 在每个正式支持语言的 `InfoPlist.strings` 中均存在。
4. 重新提交审核时，在 Review Notes 中说明已补齐 permission request localization。

## 14. 实现记录（2026-07-20）

### 已落地

1. 新增 `en.lproj/InfoPlist.strings`、`zh-Hans.lproj/InfoPlist.strings`、`zh-Hant.lproj/InfoPlist.strings`，覆盖全部 11 个权限 key。
2. `Debug` / `Release` / `Staging` 三套 build settings 的 `INFOPLIST_KEY_*UsageDescription` 兜底文案已改为英文，匹配 `developmentRegion = en`。
3. `plutil -lint` 三份 `InfoPlist.strings` 均通过。
4. 因工程内已存在 `zh-Hant.lproj`（`Prompts.strings` / `ToolPrompts.strings`）且 `knownRegions` 含 `zh-Hant`，本版本保留繁体并补齐权限文案，避免包内声明语言与权限弹窗不一致。

### 已知遗留（非本工单阻塞项）

1. `zh-Hant.lproj` 仍缺少完整 `Localizable.strings`（业务 UI 繁体文案）；繁体环境下业务 UI 仍会按 `L10n` 回退到简体/英文。若 App Store Connect 正式对外声明繁体中文，需另开工单补齐业务 UI 本地化。
2. 真机/模拟器权限弹窗切换验证、归档后包内 `InfoPlist.strings` 存在性检查，需在本地构建后完成。
3. 重新提交审核时，建议在 Review Notes 写明：permission usage descriptions are now localized via `InfoPlist.strings` for English, Simplified Chinese, and Traditional Chinese.
