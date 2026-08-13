# CHAT-000021 Chat 拍摄上传与消息卡片本地化补充需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000021 |
| 工单类型 | P1 Chat / 消息卡片 / 拍摄上传 / 天气卡片 / 本地化 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 重点文件 | `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatCaptureMessageCards.swift` |
| 补充扫描范围 | `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards` |
| 创建日期 | 2026-08-14 |
| 关联工单 | `CHAT-000020`、`AISETTINGS-000003` |
| 明确非目标 | 不改变拍摄、相册、文件选择、上传、预览、天气卡片展示逻辑；不处理日志文案；不处理服务端返回内容本地化 |

## 1. 背景与问题

`ChatCaptureMessageCards.swift` 是 Chat 内联拍摄 / 上传卡片，负责报告图片、药盒图片、皮肤照片等资料上传流程。该文件已经有部分文案接入 `L10n.text`，例如 `chat.capture_card.report.title`、`chat.capture_card.action.camera` 等，但上传状态、处理状态和 fallback 提示仍然直接写在 Swift 代码中。

另外，对 `MessageCards` 目录补充扫描后，还发现天气工具配置卡片存在硬编码标题，天气结果卡片存在资源键 fallback 与天气条件关键字匹配的本地化风险。

本工单目标是补齐 Chat 拍摄上传卡片及同目录新增发现项的本地化需求，作为 `CHAT-000020` 工具交互卡片本地化之后的补充工单。

## 2. 当前资源现状

| 资源 / key | 当前状态 | 问题 |
| --- | --- | --- |
| `chat.capture_card.*` | `zh-Hans`、`en` 已存在一部分 | 缺少状态类 key |
| `chat.attachments.camera.result` | `zh-Hans`、`en` 已存在 | 需要补繁中 |
| `ai_settings.weather.preview.*` | `zh-Hans`、`en` 已存在 | 被 Chat 天气结果卡片复用，需要确认繁中 |
| `zh-Hant.lproj/Localizable.strings` | 当前缺失 | Chat 卡片无法完整支持繁体中文 |

## 3. 未本地化检查结果

### 3.1 `ChatCaptureMessageCards.swift`

文件：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatCaptureMessageCards.swift
```

已本地化但需补齐繁中资源的 key：

| 行号 | key | 用途 |
| --- | --- | --- |
| 51 | `chat.capture_card.action.camera` | 拍照按钮 |
| 54 | `chat.capture_card.action.photo_library` | 相册按钮 |
| 58 | `chat.capture_card.action.files` | 文件按钮 |
| 133 | `chat.attachments.camera.result` | 拍摄照片默认文件名 |
| 397-418 | `chat.capture_card.report.*`、`chat.capture_card.medicine_box.*`、`chat.capture_card.skin.*` | 不同拍摄卡片标题、说明、示例 |

仍未本地化的硬编码文案：

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 217 | `已选择` | 状态 badge | 提取 key |
| 218 | `上传中` | 状态 badge | 提取 key |
| 219 | `已上传` | 状态 badge | 提取 key |
| 220 | `处理中` | 状态 badge | 提取 key |
| 221 | `已完成` | 状态 badge | 提取 key |
| 222 | `失败` | 状态 badge | 提取 key |
| 223 | `已取消` | 状态 badge | 提取 key |
| 240 | `已选择材料，准备上传。` | 状态说明 | 提取 key |
| 242 | `正在上传到安全文件存储，请稍候。` | 状态说明 | 提取 key |
| 244 | `文件已上传，正在准备给 AI 使用的材料。` | 状态说明 | 提取 key |
| 246 | `正在压缩图片并提取文字，对话稍后会自动继续。` | 状态说明 | 提取 key |
| 248 | `材料已处理完成，对话将继续。` | fallback 结果 | 提取 key |
| 250 | `上传或处理失败，可以重新选择材料。` | 状态说明 | 提取 key |
| 252 | `已取消上传。` | fallback 结果 | 提取 key |

### 3.2 `ChatWeatherConfigMessageCardView.swift`

文件：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatWeatherConfigMessageCardView.swift
```

| 行号 | 当前文案 | 类型 | 本地化要求 |
| --- | --- | --- | --- |
| 20 | `天气工具配置` | 卡片副标题 | 提取为 `chat.weather_config_card.subtitle` 或复用天气设置 key |

说明：`payload.title`、`payload.message`、`payload.actionTitle` 来自 payload，不在本工单强行改写；但需要确认 payload 创建处是否已本地化。

### 3.3 `ChatWeatherResultCardView.swift`

文件：

```text
SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatWeatherResultCardView.swift
```

该文件大部分用户可见固定文案已经使用 `L10n.text`，但存在两个问题：

| 行号 | 现状 | 问题 | 处理要求 |
| --- | --- | --- | --- |
| 76-78 | `ai_settings.weather.preview.wind/humidity/precipitation` 带中文 fallback | 需要确认资源 key 覆盖 `zh-Hans`、`en`、`zh-Hant` | 补齐繁中资源 |
| 95 | `ai_settings.weather.preview.title` 带中文 fallback | Chat 卡片复用 AI 设置天气预览 key | 确认产品是否接受复用；如不接受，新增 `chat.weather_result.*` |
| 270-283 | 使用 `rain/雨/snow/雪/cloud/云/阴/storm/雷/fog/雾` 判断图标和颜色 | 这不是 UI 文案本地化，但对多语言天气条件文本有风险 | 建议后续改为基于天气 provider condition code 或规范化枚举判断 |

### 3.4 `ChatStructuredHealthCardsBlockView.swift` 与 Preview Adapter

补充扫描发现以下 `L10n.text` fallback，需要资源侧确认完整性：

| 文件 | key / fallback | 要求 |
| --- | --- | --- |
| `ChatStructuredHealthCardsBlockView.swift` | `chat.medical_card.extraction_failed.title` / `结构化健康卡片生成失败` | 已有部分资源，但需确认文案与当前 fallback 是否一致 |
| `ChatStructuredHealthCardsBlockView.swift` | fallback `请稍后重试或补充更完整的病历摘要。` | 需要确认 key 是否存在 |
| `ChatStructuredHealthCardPreviewAdapter.swift` | `chat.medical_card.preview.unsupported` / `该卡片暂不支持详情预览` | 补齐 `zh-Hans`、`en`、`zh-Hant` |
| `ChatStructuredHealthCardPreviewAdapter.swift` | `chat.medical_card.preview.title` / `卡片预览` | 补齐 `zh-Hans`、`en`、`zh-Hant` |

### 3.5 日志文案排除项

以下文件中命中的中文主要是日志，不作为本工单实现目标：

```text
ChatHealthResourceReferenceCardViewModel.swift
```

日志文案如需治理，应另开日志治理工单；本工单只处理用户可见 UI 与可见 fallback。

## 4. 需求目标

1. `ChatCaptureMessageCards.swift` 中上传状态 badge、状态说明和 fallback 结果文案全部本地化。
2. 保留已存在的 `chat.capture_card.*` key，并补齐 `zh-Hant` 资源。
3. `ChatWeatherConfigMessageCardView.swift` 的固定副标题本地化。
4. 对 `ChatWeatherResultCardView.swift` 的天气预览资源 key 做三语言资源完整性检查。
5. 对结构化健康卡片相关 fallback key 做资源完整性检查。
6. 不改变当前拍摄、上传、文件预览、天气结果展示、结构化卡片预览逻辑。

## 5. 建议 key 命名空间

建议沿用现有命名空间：

```text
chat.capture_card.*
```

新增状态类 key：

```text
chat.capture_card.status.selected
chat.capture_card.status.uploading
chat.capture_card.status.uploaded
chat.capture_card.status.processing
chat.capture_card.status.completed
chat.capture_card.status.failed
chat.capture_card.status.cancelled
```

新增状态说明 key：

```text
chat.capture_card.status_text.selected
chat.capture_card.status_text.uploading
chat.capture_card.status_text.uploaded
chat.capture_card.status_text.processing
chat.capture_card.status_text.completed
chat.capture_card.status_text.failed
chat.capture_card.status_text.cancelled
```

天气配置卡片建议：

```text
chat.weather_config_card.subtitle
```

如果后续决定 Chat 天气结果卡片不复用 AI 设置 key，再新增：

```text
chat.weather_result.title
chat.weather_result.wind
chat.weather_result.humidity
chat.weather_result.precipitation
chat.weather_result.source_format
chat.weather_result.apple_legal_attribution
```

## 6. 推荐文案清单

### 6.1 上传状态 badge

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `chat.capture_card.status.selected` | 已选择 | Selected | 已選擇 |
| `chat.capture_card.status.uploading` | 上传中 | Uploading | 上傳中 |
| `chat.capture_card.status.uploaded` | 已上传 | Uploaded | 已上傳 |
| `chat.capture_card.status.processing` | 处理中 | Processing | 處理中 |
| `chat.capture_card.status.completed` | 已完成 | Completed | 已完成 |
| `chat.capture_card.status.failed` | 失败 | Failed | 失敗 |
| `chat.capture_card.status.cancelled` | 已取消 | Cancelled | 已取消 |

### 6.2 上传状态说明

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `chat.capture_card.status_text.selected` | 已选择材料，准备上传。 | Materials selected. Ready to upload. | 已選擇材料，準備上傳。 |
| `chat.capture_card.status_text.uploading` | 正在上传到安全文件存储，请稍候。 | Uploading to secure file storage. Please wait. | 正在上傳到安全檔案儲存空間，請稍候。 |
| `chat.capture_card.status_text.uploaded` | 文件已上传，正在准备给 AI 使用的材料。 | Files uploaded. Preparing materials for AI. | 檔案已上傳，正在準備給 AI 使用的材料。 |
| `chat.capture_card.status_text.processing` | 正在压缩图片并提取文字，对话稍后会自动继续。 | Compressing images and extracting text. The conversation will continue shortly. | 正在壓縮圖片並提取文字，對話稍後會自動繼續。 |
| `chat.capture_card.status_text.completed` | 材料已处理完成，对话将继续。 | Materials processed. The conversation will continue. | 材料已處理完成，對話將繼續。 |
| `chat.capture_card.status_text.failed` | 上传或处理失败，可以重新选择材料。 | Upload or processing failed. You can choose materials again. | 上傳或處理失敗，可以重新選擇材料。 |
| `chat.capture_card.status_text.cancelled` | 已取消上传。 | Upload cancelled. | 已取消上傳。 |

### 6.3 已存在 key 的繁中补齐

| key | zh-Hant 建议 |
| --- | --- |
| `chat.attachments.camera.result` | 拍攝照片 |
| `chat.capture_card.report.title` | 整理與查看報告資料 |
| `chat.capture_card.report.subtitle` | 請上傳清晰完整的檢查、檢驗或體檢報告。我會協助提取關鍵數值並整理報告資訊。 |
| `chat.capture_card.report.disclaimer` | 註：AI 提取和整理結果僅供健康管理參考，不構成診斷、治療建議或用藥依據。如需醫療協助，請諮詢醫師。 |
| `chat.capture_card.report.example.flat` | 平整放置 |
| `chat.capture_card.report.example.complete` | 完整拍攝 |
| `chat.capture_card.medicine_box.title` | AI 智慧識別藥盒 |
| `chat.capture_card.medicine_box.subtitle` | 請將清晰、完整的藥盒圖片傳送給我，我可以為你提供藥品的詳細內容。 |
| `chat.capture_card.medicine_box.example.flat` | 平面放置 |
| `chat.capture_card.medicine_box.example.front` | 正面拍攝 |
| `chat.capture_card.skin.title` | AI 皮膚拍照輔助 |
| `chat.capture_card.skin.subtitle` | 請在光線充足處拍攝患處清晰照片並傳送，便於後續分析與建議。 |
| `chat.capture_card.action.camera` | 拍照 |
| `chat.capture_card.action.photo_library` | 上傳照片 |
| `chat.capture_card.action.files` | 選擇檔案 |

### 6.4 天气配置与天气结果

| key | zh-Hans | en | zh-Hant |
| --- | --- | --- | --- |
| `chat.weather_config_card.subtitle` | 天气工具配置 | Weather Tool Settings | 天氣工具設定 |
| `ai_settings.weather.preview.wind` | 风速 | Wind | 風速 |
| `ai_settings.weather.preview.humidity` | 湿度 | Humidity | 濕度 |
| `ai_settings.weather.preview.precipitation` | 降水概率 | Precipitation | 降水機率 |
| `ai_settings.weather.preview.title` | 天气预览 | Weather Preview | 天氣預覽 |

## 7. 实现要求

1. `ChatCaptureMessageCards.swift` 状态文案统一通过 `L10n.text` 获取。
2. `payload.resultSummary` 属于运行时结果内容，不在展示层翻译；只本地化 fallback。
3. 已有 `chat.capture_card.*` key 不要改名，避免影响其它调用点。
4. 新增 `zh-Hant.lproj/Localizable.strings` 或按项目约定补齐繁中资源。
5. 天气条件图标 / 颜色匹配不属于普通文案本地化，建议另行排期改为 provider condition code 或规范化 condition enum。
6. 构建前需要检查新增资源是否被 Xcode target 收录。

## 8. 验收标准

1. `ChatCaptureMessageCards.swift` 中不再存在上传状态和状态说明的中文硬编码。
2. `ChatWeatherConfigMessageCardView.swift` 中不再存在 `天气工具配置` 硬编码。
3. `chat.capture_card.*`、`chat.attachments.camera.result`、`chat.weather_config_card.subtitle` 三语言资源完整。
4. 英文系统语言下，拍摄上传卡片所有固定状态均显示英文。
5. 繁体中文系统语言下，拍摄上传卡片不回退到简体中文或英文。
6. 报告图片、药盒图片、皮肤照片三类卡片的标题、说明、示例、按钮、状态展示正常。
7. 上传中、已上传、处理中、已完成、失败、取消等状态视觉和交互行为保持不变。
8. 至少完成一次 Debug 构建验证，并进行拍照 / 相册 / 文件选择入口 smoke check。

## 9. 回归检查建议

1. 触发报告上传卡片，检查默认示例、拍照、上传照片、选择文件按钮。
2. 触发药盒照片卡片，检查不展示文件按钮且状态文案本地化。
3. 触发皮肤照片卡片，检查标题、说明和状态文案。
4. 模拟 selected、uploading、uploaded、processing、completed、failed、cancelled 状态，逐一检查 badge 与正文。
5. 触发天气配置卡片，检查副标题本地化。
6. 英文与繁体中文系统语言分别走一遍上传卡片和天气配置卡片。

## 10. 后续建议

1. 后续可追加一份天气结果卡片条件匹配治理工单，把 `rain/雨/snow/雪` 等文本包含判断改成结构化天气条件。
2. 后续可把 `MessageCards` 目录纳入一个轻量 CI 检查，阻止新增用户可见中文硬编码。
