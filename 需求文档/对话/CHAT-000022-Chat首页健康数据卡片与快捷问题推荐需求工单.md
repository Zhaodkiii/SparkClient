# CHAT-000022 Chat 首页健康数据卡片与快捷问题推荐需求工单

## 0. 工单元信息

| 字段 | 内容 |
| --- | --- |
| 工单编号 | CHAT-000022 |
| 工单类型 | P1 Chat / 成员绑定对话 / 当前模型生成快捷问题 / 消息内卡片 / 后台配置 |
| 当前范围 | 创建需求与技术方案工单；本工单不直接修改业务代码 |
| 目标工程 | `/Users/hua/Documents/project/Reference/LookHealthClient/SparkClient` |
| 服务端参考工程 | `/Users/hua/Documents/project/Reference/SparkService` |
| 建议客户端目录 | `SparkClient/Projects/Features/Chat` |
| 建议服务端目录 | `ai_config`、`chat_sync`、`medical`、`nutrition` |
| 建议后台目录 | `/Users/hua/Documents/project/Reference/SparkService/backoffice-web` |
| 创建日期 | 2026-08-21 |
| 参考材料 | 用户附图 1、附图 2，仅作为 Chat 首页视觉与内容参考 |
| 关联工单 | `CHAT-000015`、`CHAT-000016`、`CHAT-000019`、`CHAT-000021` |
| 明确非目标 | 本工单不实现代码；不改 DeepTutorChat；不在客户端写死快捷问题；不由客户端自行调用模型生成问题；不新增诊断结论；不把快捷问题回答做成医疗诊断；不在未授权情况下读取 Apple 健康数据 |

## 1. 指令边界说明

用户请求是：在合适目录下创建新的需求工单，分析并规划 SparkClient Chat 对话内新增“我的健康数据卡片模块”和“快捷问题按钮组”，同时回答初始消息卡片、问答模组数据来源、按不同用户推送不同问题以及是否涉及 SparkService 的设计。

附图内容是产品参考，不是额外开发指令。附图中可采纳的信息包括：

1. Chat 初始页顶部可展示健康助手问候、健康数据摘要卡片和快捷问题列表。
2. 快捷问题使用卡片式按钮，点击后进入对话提问。
3. 健康数据卡片展示体重、步数、进度环、更新时间等轻量摘要。
4. 附图里的问题文案只作为首批种子数据参考，不作为客户端固定写死内容。客户端展示的问题必须来自 SparkService；当对话已绑定成员时，优先展示服务端使用当前对话模型生成的问题。

## 2. 背景与问题

当前 SparkClient Chat 已具备会话、消息块、健康资料引用、健康数据工具、快捷建会话和小任务能力，但用户进入 Chat 后，空会话状态更偏“输入框等待”，没有把用户已有健康数据转化为可立即提问的起点。

这会带来三个体验问题：

1. 新用户不知道可以问什么，尤其是健康管理类问题缺少起手式。
2. 已授权健康数据的用户，体重、步数、运动、营养等数据没有在 Chat 初始状态中形成“可解释入口”。
3. 快捷问题如果写死在客户端，运营无法调整问题池，也无法按不同人群动态投放。
4. 对话已经绑定成员时，用户真正需要的是结合“当前成员资料 + 当前对话历史 + 当前对话模型”生成的追问，而不只是静态问题池。

本工单目标是为 Chat 增加一个“服务端生成 + 后台配置兜底”的健康问答入口层：当对话绑定成员时，进入对话后由 SparkService 使用该会话当前模型、当前成员上下文和最近消息生成快捷问题，并以消息内卡片展示；当生成失败或不满足生成条件时，回退到后台配置的问题池。生成问题需要保存到服务器，用户点击后按普通 Chat 消息发送。

## 3. 用户故事

### 3.1 初次进入 Chat 的用户

作为普通用户，我进入 Chat 时希望看到几个由系统实时推荐的问题入口，这样我不用先组织语言，也能快速开始健康咨询。

验收标准：

- 新建或空会话中展示服务端返回的快捷问题按钮组。
- 点击快捷问题后，问题作为用户消息发送或填入输入框并触发发送，交互策略需在实现前统一。
- 发送的问题文本与按钮文本一致，便于用户理解与后续查找。
- 客户端不内置固定问题；服务端不可用时只能使用服务端下发的缓存，不再回退到客户端写死问题池。

### 3.2 已绑定健康数据的用户

作为已授权 Apple 健康或已有体重/步数数据的用户，我希望 Chat 能先展示我的关键健康数据摘要，并能一键询问这些数据代表什么。

验收标准：

- 有可用健康数据时，显示“我的健康”摘要卡片。
- 卡片至少支持体重、步数两个首期指标；可扩展体脂率、血压、睡眠、活动能量。
- 卡片显示更新时间和数据来源状态，不把示例数据误认为真实数据。
- 点击卡片或“去解读”后，生成携带当前摘要上下文的问题。

### 3.3 不同健康画像的用户

作为有不同健康目标或健康风险的用户，我希望服务端根据我的画像、健康数据和最近行为返回更贴近我的问题，而不是每个人都一样。

验收标准：

- SparkService 根据可用数据、目标、医疗画像标签、最近行为和当前对话模型生成问题；后台配置仅作为默认兜底和等级控制。
- 不满足个性化条件时，服务端返回后台配置的默认问题池。
- 后台能看到问题配置和模型生成记录，便于排查问题来源。

### 3.4 已绑定成员的对话用户

作为已在 Chat 中绑定成员的用户，我希望进入对话后看到结合当前成员和当前对话内容生成的问题，这样我可以顺着已有上下文继续问。

验收标准：

- 对话存在 `member_id` 时，进入对话后触发服务端生成快捷问题。
- 生成问题使用该对话当前配置的模型，不切换到固定模型。
- 生成依据包含当前成员摘要、最近消息摘要、健康数据摘要和必要的医疗画像摘要。
- 生成完成后，问题以消息内卡片展示在当前对话中，而不是只展示在页面空态。
- 生成结果保存到服务器，后续刷新、换设备、重新进入对话时可复用。
- 点击生成问题后，直接发送对应问题。

### 3.5 后台运营人员

作为后台运营人员，我希望在后台管理系统的 `对话` 菜单下配置快捷问题，调整上线状态、展示等级，并查看模型生成记录。

验收标准：

- `backoffice-web` 增加 `对话 / 快捷问题配置` 二级菜单。
- 支持新增、编辑、启用、停用、等级调整、查看生成记录。
- 操作需要 RBAC 菜单权限和按钮权限控制。

## 4. 需求目标

1. 在 SparkClient Chat 空会话或初始消息区域新增“我的健康数据卡片模块”。
2. 在健康数据卡片下方或消息内新增“快捷问题按钮组”。
3. 快捷问题不固定，必须从 SparkService 获取或由 SparkService 使用当前对话模型生成。
4. 对话绑定成员时，进入对话后由服务端基于当前成员、当前对话历史和当前对话模型生成问题。
5. 生成后的问题保存到服务器，并以消息内卡片展示。
6. SparkService 新增快捷问题生成、推荐、数据模型和消息块写入能力。
7. `backoffice-web` 在 `对话` 一级菜单下新增 `用户对话`、`快捷问题配置`；其中 `用户对话` 延续现有模块，`快捷问题配置` 为新增模块。
8. 支持按用户数据和当前对话上下文生成不同问题，后台只做等级与兜底配置。
9. 明确数据来源、隐私边界、客户端、服务端与后台管理系统职责。

## 5. 信息架构与展示规则

### 5.1 展示位置

建议放在 Chat 对话页的“空会话初始区”，位于首条真实用户消息之前。

展示时机：

| 场景 | 展示策略 |
| --- | --- |
| 新建空会话 | 展示健康数据卡片 + 服务端推荐问题 |
| 已绑定成员的新对话 | 进入后触发服务端生成，并在消息流内展示快捷问题卡片 |
| 已有历史消息且绑定成员 | 根据最近消息和成员上下文生成追问卡片；避免每次进入重复生成 |
| 未绑定成员的已有历史消息 | 默认不生成成员个性化问题，可展示后台默认问题或隐藏 |
| 用户下拉回到顶部 | 可展示折叠态入口，具体留待设计确认 |
| 未登录或游客模式 | 展示服务端默认快捷问题，健康数据卡片显示授权/绑定引导 |
| 无健康数据权限 | 展示空态卡片或直接隐藏健康数据卡片，保留快捷问题 |

### 5.2 初始消息卡片形态

推荐结构：

```text
Hi~ 上午好
我的专科能力达主任级医师水平

[我的健康卡片]
  标题：我的健康
  状态：更新于 HH:mm / 未授权 / 暂无数据
  指标 1：体重 65.65 kg
  指标 2：步数 267 步
  趋势：小折线或简化状态
  操作：去解读 / 展开 / 授权

[快捷问题]
  # 服务端问题 1
  # 服务端问题 2
  # 服务端问题 3
```

绑定成员后的消息内卡片结构：

```text
[assistant 消息内卡片：你可以继续问]
  说明：根据当前成员和最近对话生成
  # 最近体重变化需要注意什么？
  # 这份报告里最该复查哪一项？
  # 接下来 7 天饮食怎么安排？
```

交互建议：

| 元素 | 行为 |
| --- | --- |
| 健康数据卡片整体点击 | 展开更多指标或进入健康数据选择态 |
| `去解读` | 直接发送“请结合我的健康数据，解读当前体重、步数等指标，并给出今天的健康建议。” |
| 快捷问题按钮 | 直接发送服务端返回的问题；首期建议直接发送，减少一步操作 |
| 消息内快捷问题卡片 | 点击后把该问题作为用户消息发送；卡片保留在原消息中，刷新后可复现 |
| 无授权按钮 | 跳转设备绑定/健康权限路径，不直接发送健康数据问题 |
| 右侧箭头 | 与按钮点击同义，不单独定义第二行为 |

## 6. 数据来源设计

### 6.1 客户端健康数据来源

| 数据 | 首期用途 | 来源建议 | 是否需要服务端 |
| --- | --- | --- | --- |
| 当前选中成员 | 决定卡片归属和请求推荐问题参数 | `MemberContextStore`、成员选择持久化 | 推荐接口需要传递 |
| Apple 健康授权状态 | 判断是否展示真实健康卡片 | 现有健康数据授权/设备绑定能力 | 否 |
| 体重 | 健康卡片主指标、推荐请求特征 | HealthKit 或已同步健康数据 | 推荐接口可接收摘要 |
| 步数 | 健康卡片主指标、推荐请求特征 | HealthKit | 推荐接口可接收摘要 |
| 体脂率 | 推荐请求特征 | HealthKit bodyFatPercentage 或设备数据 | 推荐接口可接收摘要 |
| 血压 | 异常指标卡片和解读入口 | HealthKit / 手动记录 / 医疗画像 | 取决于现有接入 |
| 医疗画像标签 | 脂肪肝、慢病、用药等问题推荐 | `medical` 成员医疗画像 | 是 |
| 营养目标 | 减脂计划问题推荐 | `nutrition` goal/dashboard | 是 |
| 最近会话意图 | 避免重复推荐、延续上下文 | `chat_sync` 汇总或最近消息摘要 | 是 |
| 当前对话模型 | 生成成员个性化问题 | `ChatThread.current_model_name`、AI 场景配置 | 是 |
| 当前对话最近消息 | 生成追问问题 | `chat_sync.ChatMessage`、`ChatMessageBlock` | 是 |

### 6.2 快捷问题来源

快捷问题来源统一为 SparkService，不在 SparkClient 固定写死问题。

| 来源 | 用途 | 要求 |
| --- | --- | --- |
| 服务端问题池 | 存储可展示的问题模板 | 支持启用/停用、场景、等级、分类、上下线时间 |
| 服务端推荐接口 | 返回当前用户可见问题 | 支持 member_id、scene、limit、客户端健康摘要 |
| 服务端生成接口 | 使用当前对话模型生成问题 | 支持 thread_id、member_id、最近消息窗口、模型配置 |
| 后台配置 | 运营维护问题内容、等级和上下文策略 | 通过 `backoffice-web` 的 `对话 / 快捷问题配置` 管理 |

### 6.3 AI 问答上下文来源

快捷问题不应只把按钮文本丢给模型。建议出站消息按场景补充上下文：

| 问题类型 | 建议附加上下文 |
| --- | --- |
| 21 天健康减脂计划 | 年龄、性别、身高体重、近 7 天步数、活动能量、营养目标、既往病史摘要 |
| 脂肪肝逆转需要多久 | 是否有脂肪肝标签、最近肝功能/腹部超声/体重/BMI、饮酒与代谢风险摘要；无资料时要求 AI 先说明需要哪些信息 |
| 电子秤测体脂率准吗 | 是否有体脂率记录、设备来源、体重波动、测量时间；无资料时给通用科普 |

首期可采用“服务端问题文本 + 当前健康摘要”的轻量上下文。服务端返回的每个问题需要携带 `context_policy`，客户端据此决定是否附加健康摘要、医疗画像摘要或仅发送纯问题。

### 6.4 成员绑定对话生成上下文

当 ChatThread 已绑定 `member_id` 时，快捷问题生成不应只靠问题池等级，而应使用当前对话上下文生成。

| 上下文 | 来源 | 处理要求 |
| --- | --- | --- |
| 当前成员摘要 | `medical`、成员资料、健康数据缓存 | 服务端组装最小必要摘要，不暴露完整隐私原文 |
| 当前对话模型 | `ChatThread.current_model_name` 或线程 AI 配置 | 必须使用用户当前对话模型，不使用固定后台模型 |
| 最近消息摘要 | `chat_sync` 最近 N 条用户/助手消息 | 先裁剪、脱敏、摘要，避免 prompt 过长 |
| 最近健康资料引用 | 消息块中的健康资料引用 | 只传摘要和 resource ref，不直接传完整附件 |
| 当前健康卡片摘要 | 客户端上传或服务端可查数据 | 作为生成问题的辅助信号 |

生成结果必须推送/写入服务器，形成可同步的消息内快捷问题卡片。

## 7. 服务端快捷问题推荐策略

### 7.1 核心原则

1. 快捷问题不固定，不在 SparkClient 写死。
2. 客户端每次进入空 Chat 初始页时，从 SparkService 获取当前用户可见问题。
3. 对话绑定成员时，SparkService 使用当前对话模型生成成员个性化问题，并写入当前对话消息流。
4. SparkService 负责问题池、模型生成、等级标记和默认问题兜底。
5. `backoffice-web` 负责问题配置、上下线、等级和生成记录查看。
6. 客户端只负责展示和点击发送。

### 7.2 推荐输入信号

| 信号 | 来源 | 用途 |
| --- | --- | --- |
| `scene` | 客户端传入，如 `chat_home` | 决定问题展示场景 |
| `member_id` | 当前选中成员 | 决定问题归属与画像读取 |
| 用户基础信息 | 账号/成员资料 | 粗分人群，如年龄段、性别 |
| 健康摘要 | 客户端本地健康数据摘要或服务端同步数据 | 判断减脂、运动、体脂率等问题优先级 |
| 医疗画像 | `medical` | 判断脂肪肝、慢病、用药、体检报告等问题 |
| 营养目标 | `nutrition` | 判断减脂、控糖、蛋白摄入等问题 |
| 最近会话行为 | `chat_sync` | 避免重复推荐，延续最近咨询主题 |
| 后台配置等级 | 快捷问题配置表 | 控制问题粗粒度展示优先级 |
| 当前对话模型 | `ChatThread.current_model_name` | 生成问题时选择模型 |
| 当前对话历史 | `chat_sync` 最近消息 | 生成贴合当前上下文的追问 |

### 7.3 推荐规则示例

| 用户信号 | 服务端推荐表现 |
| --- | --- |
| 有体重数据且 BMI 偏高或设置减脂目标 | 减脂计划类问题优先 |
| 有脂肪肝医疗画像标签、体检报告提示脂肪肝、肝功能异常 | 脂肪肝科普/逆转类问题优先 |
| 有体脂率记录或体重秤数据来源 | 体脂率测量准确性类问题优先 |
| 后台设置某问题为 `level=1` | 在同类候选问题中优先展示 |
| 对话绑定成员且最近消息包含报告/指标/计划 | 使用当前模型生成上下文追问，并优先展示生成问题 |
| 没有任何命中信号 | 返回后台配置的默认问题池 |

说明：附图中的 3 个问题可作为服务端初始种子数据，但客户端不得固定这 3 个问题。

### 7.4 生成触发策略

| 触发点 | 生成策略 |
| --- | --- |
| 进入已绑定成员的空会话 | 可生成一次成员起始问题卡片，但必须使用低打扰空态样式 |
| 进入已有消息的绑定成员会话 | 不建议立即插入新消息；仅加载最近已生成且未过期的卡片 |
| 用户连续发送多条消息后 | 等待本轮 AI 回复完成，再基于多消息窗口生成追问 |
| 用户发送新消息并收到 AI 回复后 | 可异步生成下一组追问，优先作为该助手回复的附加 block |
| 成员切换 | 旧成员生成问题失效，重新按新成员生成 |
| 模型切换 | 旧生成问题可保留，但新生成任务必须使用新模型 |

去重要求：

1. 同一 `thread_id + member_id + message_window_hash + model_name` 不重复生成。
2. 最近消息中已经发送过的问题文本不应在短时间内重复出现。
3. 生成失败时回退后台问题池，不阻塞对话加载。

### 7.5 多消息上下文与修正后的业务流程

当前“进入对话即生成”的流程不够合理，原因是用户刚进入对话时意图不一定明确，系统主动插入问题容易像运营位，也会污染消息流。更合理的流程是以“对话轮次”为单位，在用户表达意图并收到 AI 回复后生成追问。

#### 7.5.1 多消息窗口定义

```text
message_window =
  最近 1 个完整对话轮次
  + 当前成员摘要
  + 最近用户连续消息
  + 最近 assistant 最终回复
  + 最近健康资料引用/健康数据摘要
```

连续多消息场景：

| 场景 | 处理 |
| --- | --- |
| 用户连续发 2-3 条消息，AI 尚未回复 | 不生成；等待 assistant 回复完成 |
| 用户补充图片/报告/文字后 AI 回复 | 基于完整输入和回复生成追问 |
| AI 正在 streaming | 不生成；避免基于半截回复出问题 |
| 用户围绕旧问题继续追问 | 以最近真实消息为准，不依赖行为记录；避免生成同义重复问题 |
| 会话有多条历史消息但最近无新互动 | 不主动插入新卡片，只展示已有未过期卡片 |

#### 7.5.2 修正后的主流程

```text
用户进入 Chat
  ↓
加载历史消息和已有 quickQuestionSuggestions block
  ↓
如果是空会话：展示健康卡片 + 服务端默认/成员起始问题
  ↓
如果是已有会话：不因“进入页面”立即插入新问题
  ↓
用户发送一条或多条消息
  ↓
AI 使用当前对话模型完成回复
  ↓
服务端基于本轮多消息窗口判断是否值得生成追问
  ↓
值得生成：追加 quickQuestionSuggestions block
不值得生成：不展示，避免低质量打扰
  ↓
用户点击问题：直接发送问题
```

#### 7.5.3 是否值得生成的门槛

| 条件 | 生成策略 |
| --- | --- |
| assistant 回复过短或只是寒暄 | 不生成 |
| 用户问题已被完整回答且无明显后续路径 | 可不生成 |
| 当前轮涉及报告、指标、计划、用药、饮食、复查 | 生成 2-3 个追问 |
| 当前轮涉及敏感医疗风险 | 只生成“补充信息/咨询医生/复查建议”类谨慎问题 |
| 最近 24 小时同 thread 已生成 3 次 | 降频或不生成 |

### 7.6 不合理点与流程风险分析

| 现有设想 | 不合理点 | 可能导致 |
| --- | --- | --- |
| 进入绑定成员对话就生成 | 用户此时只是查看历史，不一定想继续问 | 消息流被动插入，打扰感强 |
| 独立 assistant 消息承载问题卡片 | 容易像系统插入广告，割裂聊天节奏 | 用户忽略或反感 |
| 每次进入都检查生成 | 幂等稍弱就会重复卡片污染消息流 | 会话变乱，信任下降 |
| 静态问题池兜底太强 | 问题和当前上下文不贴合 | 看起来模板化 |
| 问题太泛 | 用户觉得“我自己也能问” | 没有点击动机 |
| 问题太医疗化 | 用户担心被诊断或焦虑 | 合规风险或信任下降 |

改造原则：

1. 从“页面入口”改为“AI 回复后的下一步辅助”。
2. 从“每次进入生成”改为“有明确上下文、有后续价值才生成”。
3. 从“独立消息优先”改为“优先附加到 assistant 回复末尾；MVP 如果独立消息，也必须低频且可折叠”。

## 8. SparkService 接口与数据模型方案

### 8.1 对话内生成接口

建议新增：

```text
POST /api/chat/quick-questions/generate/
```

请求示例：

```json
{
  "thread_id": "0EF5BCA4-5E88-41F3-97E9-5F2D2F0F9A11",
  "member_id": 123,
  "scene": "chat_thread_inline",
  "limit": 3,
  "trigger": "thread_enter",
  "client_context": {
    "locale": "zh-Hans",
    "app_version": "1.0.0",
    "visible_message_count": 20
  }
}
```

服务端处理：

1. 读取 `ChatThread.current_model_name`、温度、角色提示词等当前会话模型配置。
2. 读取当前成员摘要、健康数据摘要、医疗画像摘要。
3. 读取当前对话最近消息，生成短摘要，不直接把完整敏感原文长期写入日志。
4. 使用当前对话模型生成 1-3 个问题。
5. 将生成批次、生成问题和推荐理由保存到服务器。
6. 将问题卡片写入当前对话的消息流，形成可同步的 `ChatMessageBlock`。

返回示例：

```json
{
  "batch_id": "qqg_202608210834_abcdef",
  "thread_id": "0EF5BCA4-5E88-41F3-97E9-5F2D2F0F9A11",
  "member_id": 123,
  "model_name": "current-thread-model",
  "message_block_id": "2C7E91EF-010F-4A7E-95D6-C10F904B08B3",
  "items": [
    {
      "id": 2001,
      "text": "最近体重变化需要注意什么？",
      "level": 1,
      "reason_code": "member_weight_context",
      "context_policy": "health_summary",
      "source": "model_generated"
    }
  ]
}
```

生成接口要求：

1. 只有当前用户拥有该 thread 和 member 权限时才允许生成。
2. `member_id` 必须与 thread 当前绑定成员一致；如允许临时成员覆盖，需要单独设计。
3. 生成任务必须幂等，避免每次进入对话都插入新卡片。
4. 模型生成失败时，服务端可返回后台配置问题池，但 `source` 必须标识为 `configured_fallback`。
5. 生成卡片入库后，通过现有 `chat_sync` 增量同步给客户端。

### 8.2 客户端推荐接口

建议新增：

```text
POST /api/chat/quick-questions/recommendations/
```

请求示例：

```json
{
  "scene": "chat_home",
  "member_id": 123,
  "limit": 3,
  "client_context": {
    "locale": "zh-Hans",
    "app_version": "1.0.0",
    "health_summary": {
      "has_weight": true,
      "weight_kg": 65.65,
      "has_steps_today": true,
      "steps_today": 267,
      "has_body_fat": false,
      "updated_at": "2026-08-21T08:34:00+08:00"
    }
  }
}
```

返回示例：

```json
{
  "scene": "chat_home",
  "request_id": "qqr_202608210834_abcdef",
  "member_id": 123,
  "expires_in_seconds": 600,
  "items": [
    {
      "id": 1001,
      "code": "weight_loss_21_days",
      "text": "如何制定 21 天健康减脂计划？",
      "category": "weight_management",
      "level": 1,
      "reason_code": "weight_or_goal_matched",
      "context_policy": "health_summary"
    }
  ]
}
```

要求：

1. `items` 最多返回 `limit` 条。
2. `level` 只表示展示等级：`1` 优先展示、`2` 普通、`3` 低优先级；不再设计行为分析字段或复杂推荐分值。
3. 服务端无可用问题时返回空列表，客户端显示无问题空态或隐藏快捷问题区域。
4. 客户端可以缓存最近一次成功结果，但缓存必须受 `expires_in_seconds` 控制。

### 8.3 管理端接口

建议在后台管理 API 增加：

```text
GET    /api/admin/v1/chat/quick-questions/
POST   /api/admin/v1/chat/quick-questions/
GET    /api/admin/v1/chat/quick-questions/{id}/
PATCH  /api/admin/v1/chat/quick-questions/{id}/
POST   /api/admin/v1/chat/quick-questions/{id}/enable/
POST   /api/admin/v1/chat/quick-questions/{id}/disable/
PATCH  /api/admin/v1/chat/quick-questions/{id}/level/
GET    /api/admin/v1/chat/quick-questions/generated/
GET    /api/admin/v1/chat/quick-questions/generated/{batch_id}/
```

后台列表筛选：

| 筛选项 | 说明 |
| --- | --- |
| 场景 | 如 `chat_home` |
| 状态 | 草稿、已启用、已停用、已过期 |
| 分类 | 减脂、脂肪肝、体脂率、血压、报告解读等 |
| 创建/更新时间 | 后台维护查询 |

### 8.4 数据模型建议

不新建独立 Django app，直接在现有 `ai_config` 内新增快捷问题模板、生成批次、生成问题与后台配置相关模块；消息展示仍写入 `chat_sync.ChatMessageBlock`。服务端生成的问题只做轻量等级，不单独维护行为分析字段或复杂推荐日志。

| 模型 | 用途 | 关键字段 |
| --- | --- | --- |
| `ChatQuickQuestion` | 问题模板主表 | code、scene、title/text、category、status、level、context_policy、start_at、end_at |
| `ChatQuickQuestionLocale` | 多语言文案 | question、locale、text、subtitle |
| `ChatGeneratedQuickQuestionBatch` | 模型生成批次 | batch_id、thread、member_id、model_name、trigger、source_message_revision、status |
| `ChatGeneratedQuickQuestion` | 模型生成的问题 | batch、text、level、reason_code、context_policy |
| `ChatQuickQuestionAuditLog` | 后台操作审计 | operator、action、before_json、after_json |

### 8.5 消息块 payload 建议

建议在 Chat 消息块中新增快捷问题卡片 payload，或复用现有 rich block 体系增加 kind：

```json
{
  "kind": "quickQuestionSuggestions",
  "status": "ready",
  "payload": {
    "batch_id": "qqg_202608210834_abcdef",
    "source": "model_generated",
    "title": "你可以继续问",
    "subtitle": "根据当前成员和最近对话生成",
    "items": [
      {
        "id": 2001,
        "text": "最近体重变化需要注意什么？",
        "level": 1,
        "context_policy": "health_summary"
      }
    ]
  }
}
```

要求：

1. payload 必须能通过 `chat_sync` 同步到多端。
2. 卡片属于助手消息的一部分，不作为用户消息。
3. 用户点击问题后，生成新的用户消息；原卡片状态可保留，也可局部标记“已使用”。
4. 卡片 payload 不写入完整健康原始数据，只写展示问题、等级和上下文策略。

### 8.6 初始种子数据

附图中的 3 个问题可作为服务端种子数据：

| code | text | category | context_policy |
| --- | --- | --- | --- |
| `weight_loss_21_days` | 如何制定 21 天健康减脂计划？ | `weight_management` | `health_summary` |
| `fatty_liver_reverse_duration` | 脂肪肝逆转需要多久？ | `liver_health` | `medical_profile_summary` |
| `body_fat_scale_accuracy` | 用电子秤测体脂率准吗？ | `body_composition` | `health_summary` |

种子数据只写入 SparkService 数据库或初始化脚本，不进入 SparkClient 常量。

### 8.7 与现有服务端模块关系

| 模块 | 关系 |
| --- | --- |
| `chat_sync` | 已承载 ChatThread、ChatMessage、ChatMessageBlock；快捷问题发送后的真实对话仍走现有消息同步 |
| `ai_config` | 可承载快捷问题模板、等级配置、AI 场景配置；也可作为后台管理入口复用 |
| `medical` | 提供成员医疗画像、体检报告标签、脂肪肝等疾病/风险信号 |
| `nutrition` | 提供减脂目标、饮食目标、能量消耗等营养健康管理信号 |
| `backoffice-web` | 提供快捷问题配置和生成记录查看页面 |

### 8.8 Django 模型结构草案

以下为落地时可参考的数据模型结构，字段命名需按 SparkService 现有 Django 风格调整。

```python
class ChatQuickQuestion(models.Model):
    class Status(models.TextChoices):
        DRAFT = "draft"
        ENABLED = "enabled"
        DISABLED = "disabled"
        EXPIRED = "expired"

    code = models.CharField(max_length=128, unique=True)
    scene = models.CharField(max_length=64, db_index=True, default="chat_home")
    category = models.CharField(max_length=64, db_index=True)
    text = models.CharField(max_length=200)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.DRAFT, db_index=True)
    level = models.PositiveSmallIntegerField(default=2, db_index=True)
    context_policy = models.CharField(max_length=64, default="none")
    allow_as_generation_fallback = models.BooleanField(default=True)
    prompt_hint = models.TextField(blank=True, default="")
    start_at = models.DateTimeField(null=True, blank=True)
    end_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class ChatGeneratedQuickQuestionBatch(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending"
        READY = "ready"
        FAILED = "failed"

    batch_id = models.CharField(max_length=64, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    thread = models.ForeignKey("chat_sync.ChatThread", on_delete=models.CASCADE)
    member_id = models.IntegerField(db_index=True)
    model_name = models.CharField(max_length=128, blank=True, default="")
    trigger = models.CharField(max_length=64, db_index=True)
    scene = models.CharField(max_length=64, db_index=True, default="chat_thread_inline")
    source_message_revision = models.CharField(max_length=128, blank=True, default="")
    message_block_id = models.UUIDField(null=True, blank=True, db_index=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING, db_index=True)
    error_message = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class ChatGeneratedQuickQuestion(models.Model):
    batch = models.ForeignKey(ChatGeneratedQuickQuestionBatch, related_name="questions", on_delete=models.CASCADE)
    text = models.CharField(max_length=200)
    level = models.PositiveSmallIntegerField(default=2, db_index=True)
    reason_code = models.CharField(max_length=64, blank=True, default="")
    context_policy = models.CharField(max_length=64, default="none")
    created_at = models.DateTimeField(auto_now_add=True)
```

索引要求：

| 表 | 索引 |
| --- | --- |
| `ChatQuickQuestion` | `scene + status + level`、`category`、`start_at/end_at` |
| `ChatGeneratedQuickQuestionBatch` | `user + thread + member_id + status`、`batch_id`、`message_block_id` |
| `ChatGeneratedQuickQuestion` | `batch + level` |

## 9. backoffice-web 后台管理方案

### 9.1 菜单结构

当前后台已有 `对话 / 用户对话` 路由与页面，建议在同一一级菜单下新增：

| 菜单层级 | 菜单名 | 路由建议 | 权限码建议 |
| --- | --- | --- | --- |
| 一级菜单 | 对话 | `/conversations` | `menu:conversations` |
| 二级菜单 | 用户对话 | `/conversations/users` | `menu:conversations:users` |
| 二级菜单 | 快捷问题配置 | `/conversations/quick-questions` | `menu:conversations:quick_questions` |

实现注意：

1. `backoffice-web/src/router/routes.ts` 需要新增 `/conversations/quick-questions` 路由。
2. `backoffice-web/src/layouts/AdminLayout.vue` 的 fallback menu 需要增加 `快捷问题配置` 子菜单。
3. 当前代码存在过滤 `menu:conversations` 的逻辑，实施时需确认是否仍需要隐藏对话菜单；若要展示 `对话` 菜单，应移除或调整该过滤。
4. 后台 RBAC 初始化需要增加菜单权限、按钮权限和 API 权限。

### 9.2 页面能力

`快捷问题配置` 页面建议包含：

| 区域 | 能力 |
| --- | --- |
| 顶部筛选 | 场景、状态、分类、关键字、日期 |
| 列表表格 | 问题文案、分类、场景、状态、等级、更新时间 |
| 操作列 | 编辑、启用、停用、复制、调整等级 |
| 编辑抽屉 | 基础信息、文案、多语言、等级、上下线时间、上下文策略 |
| 生成记录 | 查看模型生成批次、所属用户/成员/会话、模型名称、生成问题 |

### 9.3 字段要求

| 字段 | 要求 |
| --- | --- |
| 问题文案 | 必填，建议 8-40 个中文字符，移动端需完整展示 |
| 场景 | 必填，首期支持 `chat_home` |
| 分类 | 必填，用于后台筛选和推荐策略 |
| 状态 | 草稿、已启用、已停用、已过期 |
| 等级 | `1` 高优先级、`2` 普通、`3` 低优先级；只用于展示优先级和运营粗分层 |
| 上下线时间 | 可为空；为空表示长期有效 |
| 上下文策略 | `none`、`health_summary`、`medical_profile_summary`、`nutrition_goal_summary` |
| 是否允许作为生成兜底 | 可选；模型生成失败时是否可被推荐接口回退 |
| 生成提示词片段 | 可选；作为生成问题的风格/边界配置，不直接暴露给客户端 |

## 10. 客户端实现范围建议

### 10.1 新增领域模型

建议在 Chat Feature 内建立展示模型，而不是直接把 HealthKit/服务端 DTO 泄露到 UI：

```text
ChatHomeHealthSnapshot
ChatHomeHealthMetric
ChatHomeSuggestedQuestion
ChatHomeGeneratedQuestionBatch
ChatHomeSuggestionContext
ChatHomeSuggestionSource
```

字段建议：

| 模型 | 关键字段 |
| --- | --- |
| `ChatHomeHealthSnapshot` | memberID、updatedAt、metrics、authorizationState、source |
| `ChatHomeHealthMetric` | type、displayName、valueText、trend、severity、source |
| `ChatHomeSuggestedQuestion` | id、code、generatedQuestionID、batchID、text、category、level、requestID、source、contextPolicy |
| `ChatHomeGeneratedQuestionBatch` | batchID、threadID、memberID、modelName、messageBlockID、items |
| `ChatHomeSuggestionContext` | selectedMember、healthSummaryText、medicalTags、nutritionGoal |

### 10.2 新增服务/用例

```text
LoadChatHomeHealthSnapshotUseCase
LoadChatHomeSuggestedQuestionsUseCase
GenerateChatThreadQuickQuestionsUseCase
BuildChatHomeQuickQuestionMessageUseCase
```

职责：

| 用例 | 职责 |
| --- | --- |
| `LoadChatHomeHealthSnapshotUseCase` | 聚合当前成员的体重、步数、体脂率、授权状态和更新时间 |
| `LoadChatHomeSuggestedQuestionsUseCase` | 调用 SparkService 推荐接口获取最多 3 个问题 |
| `GenerateChatThreadQuickQuestionsUseCase` | 对绑定成员的会话调用生成接口，并等待消息块同步或直接合并返回卡片 |
| `BuildChatHomeQuickQuestionMessageUseCase` | 点击问题时生成用户可见文本和 AI 隐式上下文 |

### 10.3 建议 UI 组件

```text
ChatHomeStarterPanelView
ChatHomeHealthSnapshotCardView
ChatHomeSuggestedQuestionListView
ChatHomeSuggestedQuestionRow
ChatInlineQuickQuestionCardView
```

组件要求：

1. UI 只消费展示模型，不直接读取 HealthKit 或网络。
2. 空态、授权态、加载态、失败态都要可预览。
3. 长文案问题需支持多行，不挤压箭头和图标。
4. VoiceOver 能读出“问题按钮”和“健康数据更新时间”。
5. 需要接入本地化资源，不硬编码中文在 UI 组件中。
6. 服务端无问题时隐藏快捷问题区域或展示轻量空态，不使用客户端固定问题。
7. 绑定成员对话中的生成问题优先渲染为消息内卡片，刷新后由消息块复原。

### 10.4 Plain Text UI 草图

#### 10.4.1 空会话初始态

```text
┌────────────────────────────────────────────┐
│ Chat 顶部导航                              │
│  阿福 / 当前成员 / 模型 / 更多             │
└────────────────────────────────────────────┘

Hi~ 上午好
我的专科能力达主任级医师水平

┌────────────────────────────────────────────┐
│ 我的健康                         更新于08:34 │
│                                            │
│ 体重 65.65 kg        步数 267 步            │
│ ─╲__╱─               ○ 2%                  │
│                                            │
│ [去解读]                                   │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ # 如何制定 21 天健康减脂计划？          >   │
├────────────────────────────────────────────┤
│ # 脂肪肝逆转需要多久？                  >   │
├────────────────────────────────────────────┤
│ # 用电子秤测体脂率准吗？                >   │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│ 输入框：回答将结合当前成员的个性化数据       │
└────────────────────────────────────────────┘
```

说明：

1. 问题文案来自 SparkService，不在客户端固定。
2. 空会话问题来源优先级：服务端生成问题 > 服务端推荐问题 > 后台默认问题池 > 隐藏问题区。
3. 健康数据卡片可以独立于问题区加载，问题接口慢时先展示健康卡片骨架。

#### 10.4.2 已绑定成员的消息内卡片

```text
用户：
  我的体重最近有点波动，饮食上要注意什么？

AI：
  体重短期波动常见原因包括水分、盐分摄入、运动恢复和睡眠……

  ┌────────────────────────────────────────┐
  │ 你可以继续问                           │
  │ 根据「阿福」和最近对话生成              │
  │                                        │
  │ # 最近体重变化需要注意什么？        >   │
  │ # 接下来 7 天饮食怎么安排？         >   │
  │ # 要不要关注体脂率而不是体重？      >   │
  └────────────────────────────────────────┘

输入框：
  点击输入 或 长按说话
```

说明：

1. 卡片属于 assistant 消息的一部分，刷新后从 `ChatMessageBlock` 还原。
2. 点击某个问题时，生成新的 user 消息，原 assistant 卡片保留。
3. 卡片 subtitle 不展示敏感详情，只说明“根据当前成员和最近对话生成”。

#### 10.4.3 生成中状态

```text
AI：
  ┌────────────────────────────────────────┐
  │ 正在生成可继续追问的问题...             │
  │ · 当前成员：阿福                        │
  │ · 当前模型：沿用本会话模型              │
  └────────────────────────────────────────┘
```

说明：

1. 生成中卡片最多停留一个短周期；超时后隐藏或显示后台默认问题。
2. 生成失败不能阻塞用户继续输入。

#### 10.4.4 无成员绑定状态

```text
AI：
  ┌────────────────────────────────────────┐
  │ 想让我结合个人数据回答？                │
  │ 先选择一个家庭成员，我会基于该成员生成问题 │
  │                                        │
  │ [选择成员]                              │
  └────────────────────────────────────────┘
```

说明：

1. 无成员时不生成成员个性化问题。
2. 可以展示后台默认问题，但不得伪装为“基于当前成员生成”。

#### 10.4.5 后台快捷问题配置页

```text
对话 / 快捷问题配置

筛选：
[场景: chat_home v] [状态: 全部 v] [分类: 全部 v] [搜索问题]

┌────┬────────────────────────────┬────────┬──────┬────────────┐
│等级│ 问题                         │ 分类   │状态  │更新时间      │
├────┼────────────────────────────┼────────┼──────┼────────────┤
│1   │ 如何制定 21 天健康减脂计划？ │ 减脂   │启用  │08-21 08:34 │
│2   │ 脂肪肝逆转需要多久？         │ 肝健康 │启用  │08-21 08:34 │
└────┴────────────────────────────┴────────┴──────┴────────────┘

操作：
[新增问题] [批量停用] [查看生成记录]
```

#### 10.4.6 后台生成记录页

```text
对话 / 快捷问题配置 / 生成记录

筛选：
[模型] [成员ID] [用户ID] [会话ID] [生成状态] [日期范围]

┌──────────────┬────────┬────────┬────────────┬────────┬────────────┐
│生成批次       │用户/成员│会话    │模型         │状态    │生成时间      │
├──────────────┼────────┼────────┼────────────┼────────┼────────────┤
│qqg_...abcdef │102/123 │0EF5... │gpt-4.1... │ready   │08-21 08:34 │
└──────────────┴────────┴────────┴────────────┴────────┴────────────┘

展开批次：
  1. 最近体重变化需要注意什么？
  2. 接下来 7 天饮食怎么安排？
  3. 要不要关注体脂率而不是体重？
```

## 11. 初始问题发送策略

建议首期采用“直接发送”，而不是只填入输入框。

理由：

1. 快捷问题本质是行动入口，直接发送可减少一步。
2. Chat 已有快捷建会话和小任务发送链路，可对齐现有行为。
3. 用户仍可在输入框中自由提问，不需要把快捷问题当草稿编辑器。

发送格式：

| 场景 | 用户可见消息 | AI 上下文 |
| --- | --- | --- |
| 点击服务端问题 | 与服务端返回的 `text` 一致 | 根据 `context_policy` 附加上下文 |
| 点击模型生成问题 | 与生成问题 `text` 一致 | 根据生成批次的 `context_policy` 和服务端记录附加上下文 |
| 点击健康卡片解读 | “请结合我的健康数据，解读当前状态并给出今天的建议。” | 当前健康摘要 |

注意：AI 上下文应作为系统/工具上下文或出站上下文补充，不应把用户看不懂的原始数据拼进可见消息。

发送元数据建议：

1. 点击生成问题后，创建普通用户消息。
2. 用户消息 metadata 可选记录 `source_quick_question_batch_id`、`source_generated_question_id`、`source_quick_question_level`。
3. 这些字段只用于排查问题来源和复现上下文。

## 12. 变动文件清单建议

### 12.1 SparkClient

| 文件 | 变更 |
| --- | --- |
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessage.swift` | `ChatMessageBlockKind` 新增 `quickQuestionSuggestions` |
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage/BlockPayloads/ChatQuickQuestionSuggestionPayload.swift` | 新增 payload 模型 |
| `SparkClient/Projects/Features/Chat/Domain/ChatMessage/ChatMessageBlockPayload.swift` | 新增 payload case、Codable 映射 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatMessageBlock+Render.swift` | 新增渲染分支 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/MessageCards/ChatQuickQuestionSuggestionsCardView.swift` | 新增消息内快捷问题卡片 |
| `SparkClient/Projects/Features/Chat/Presentation/ChatView/Components/ChatRenderContext.swift` | 增加点击快捷问题回调 |
| `SparkClient/Projects/Features/Chat/Application/QuickQuestions/GenerateChatThreadQuickQuestionsUseCase.swift` | 调用生成接口 |
| `SparkClient/Projects/Core/Networking/API/AI/ChatQuickQuestionAPI.swift` | 新增推荐、生成 API |
| `SparkClient/Projects/Features/Chat/Application/SendChatMessageUseCase.swift` | 点击问题发送时附带生成问题来源 metadata |
| `SparkClient/Tests/Chat/ChatQuickQuestionPayloadTests.swift` | payload 编解码测试 |

### 12.2 SparkService

| 文件 | 变更 |
| --- | --- |
| `ai_config/models.py` | 新增快捷问题模板、生成批次、生成问题表 |
| `ai_config/quick_question_serializers.py` | 新增推荐、生成、后台管理 serializer |
| `ai_config/quick_question_views.py` | 新增客户端和后台 API |
| `ai_config/urls.py` | 新增快捷问题 URL 路由 |
| `ai_config/services/quick_question_generation_service.py` | 当前模型生成问题核心服务 |
| `ai_config/services/quick_question_context_builder.py` | 成员、健康数据、最近消息上下文组装 |
| `ai_config/services/quick_question_message_block_writer.py` | 写入 `chat_sync.ChatMessageBlock` |
| `chat_sync/models.py` | 如不新增表则无需改；只消费现有 `ChatMessageBlock.kind/payload` |
| `chat_sync/views.py` | 通常无需改，已有 JSON block 同步；如需白名单校验再补 |
| `backoffice/views.py` 或新 admin API 模块 | 后台列表、详情接口 |
| `ai_config/migrations/00xx_chat_quick_questions.py` | 数据表迁移 |
| `tests/test_chat_quick_questions.py` | 生成、推荐、幂等测试 |

### 12.3 backoffice-web

| 文件 | 变更 |
| --- | --- |
| `backoffice-web/src/router/routes.ts` | 新增 `/conversations/quick-questions`、生成记录详情路由 |
| `backoffice-web/src/layouts/AdminLayout.vue` | `对话` 菜单新增 `快捷问题配置`；确认是否移除 `menu:conversations` 过滤 |
| `backoffice-web/src/api/modules/quickQuestions.ts` | 新增后台 API client |
| `backoffice-web/src/views/ConversationQuickQuestionsView.vue` | 快捷问题配置列表页 |
| `backoffice-web/src/views/ConversationQuickQuestionGeneratedView.vue` | 生成记录页 |
| `backoffice-web/src/components/conversations/QuickQuestionEditorDrawer.vue` | 新增/编辑抽屉 |
| `backoffice-web/src/types/quickQuestions.ts` | 类型定义 |

## 13. 核心技术方案

### 13.1 端到端流程

```text
用户进入 Chat
  ↓
客户端判断 thread 是否绑定 member_id
  ↓
加载历史消息和已有 quickQuestionSuggestions block
  ↓
空会话：POST /api/chat/quick-questions/recommendations/
已有会话：不因进入页面立即生成
  ↓
用户发送一条或多条消息
  ↓
AI 使用当前对话模型完成回复
  ↓
服务端汇总多消息窗口：
  thread model + member summary + user messages + assistant reply + health refs
  ↓
判断是否值得生成
  ↓
值得生成：POST /api/chat/quick-questions/generate/
不值得生成：结束，不打扰用户
  ↓
生成 1-3 个问题，保存 batch/questions，写入 ChatMessageBlock(kind=quickQuestionSuggestions)
  ↓
chat_sync 增量同步到客户端，客户端渲染 ChatInlineQuickQuestionCardView
  ↓
用户点击问题，创建 user message
```

### 13.2 幂等设计

生成接口需要避免重复插入卡片。

```text
message_window_hash = sha256(
  latest_user_message_ids + latest_assistant_message_id + latest_block_revisions + health_ref_ids
)

dedupe_key = sha256(
  user_id + thread_id + member_id + model_name + trigger + message_window_hash
)
```

建议落库字段：

| 字段 | 用途 |
| --- | --- |
| `source_message_revision` | 标识本次生成基于哪个消息版本 |
| `message_window_hash` | 标识本次生成基于哪组多消息上下文 |
| `model_name` | 当前会话模型名 |
| `trigger` | `thread_enter`、`assistant_reply_completed`、`member_changed` |
| `status` | pending、ready、failed |

如果同一个 dedupe key 已有 ready 批次，直接返回已有 batch 和 message block，不重复调用模型。

### 13.2.1 生成价值判断

生成服务在调用模型前应先做轻量规则判断，避免浪费模型成本和制造低质量卡片。

```python
def should_generate_quick_questions(window: MessageWindow, thread_stats: ThreadQuickQuestionStats) -> bool:
    if window.assistant_reply_is_streaming:
        return False
    if window.assistant_reply_length < 80 and not window.has_health_resource_refs:
        return False
    if thread_stats.generated_batches_today >= 3:
        return False
    return window.has_health_topic_signal
```

`has_health_topic_signal` 可由以下信号组成：

| 信号 | 示例 |
| --- | --- |
| 健康资料引用 | 报告、用药、病历、体检计划 |
| 指标讨论 | 体重、血压、血糖、脂肪肝、睡眠、步数 |
| 计划类意图 | 减脂计划、复查计划、饮食计划、运动计划 |
| 用户追问倾向 | “怎么办”“要多久”“需要复查吗”“怎么安排” |

### 13.3 当前模型调用策略

要求：

1. 生成问题使用 `ChatThread.current_model_name`。
2. 如果 thread 未设置模型，则沿用 Chat 当前默认模型配置。
3. 生成问题的 prompt 必须明确“只输出问题，不输出诊断，不输出回答”。
4. 输出结构必须是 JSON，服务端做 schema 校验。
5. 模型返回不合规时，丢弃生成结果，回退后台配置问题池。

生成 prompt 核心约束：

```text
你是健康咨询对话中的“后续问题生成器”。
请基于当前成员摘要和最近对话，生成 1-3 个用户可能继续追问的问题。
要求：
1. 只生成问题，不回答问题。
2. 不做诊断，不暗示用户已患某病。
3. 问题必须短、具体、适合按钮展示。
4. 每个问题不超过 28 个中文字符。
5. 输出 JSON：{"questions":[{"text":"...","level":1,"reason_code":"...","context_policy":"..."}]}，其中 `level` 只能为 1、2、3。
```

### 13.4 消息块写入策略

建议服务端创建一条 assistant 消息或向最近 assistant 消息追加 block，二选一：

| 方案 | 优点 | 风险 | 建议 |
| --- | --- | --- | --- |
| 创建独立 assistant 消息 | 同步和恢复简单，卡片生命周期清晰 | 消息流会多一条助手卡片，低使用率风险更高 | 仅用于空会话或生成延迟较长场景 |
| 追加到最近 assistant 消息 | 体验更像“回复后的追问”，点击意图更自然 | 需要处理 block revision、并发更新 | 推荐方向 |

修正建议：

1. 空会话起始问题可以使用独立 assistant 卡片。
2. 已有对话的追问问题优先追加到最近 assistant 回复末尾。
3. 如果技术上暂时无法追加 block，MVP 可创建独立 assistant 消息，但必须：
   - 限制频率。
   - 卡片样式更轻。
   - 不在用户仅查看历史时插入。
   - 支持折叠或一键隐藏。

## 14. 关键代码示例

### 14.1 SparkClient payload 模型示例

```swift
struct ChatQuickQuestionSuggestionsPayload: Codable, Equatable, Sendable {
    struct Item: Codable, Identifiable, Equatable, Sendable {
        let id: Int
        let text: String
        let level: Int
        let contextPolicy: String
    }

    let batchID: String
    let source: String
    let title: String
    let subtitle: String?
    let items: [Item]
}
```

### 14.2 SparkClient block kind 示例

```swift
nonisolated enum ChatMessageBlockKind: String, Codable, Sendable {
    case text
    // ...
    case quickQuestionSuggestions
}
```

### 14.3 SparkClient 渲染分支示例

```swift
case .quickQuestionSuggestions(let payload):
    ChatInlineQuickQuestionCardView(
        payload: payload,
        onTapItem: { item in
            context.onQuickQuestionTap(payload, item)
        }
    )
```

### 14.4 SparkClient 点击发送示例

```swift
func handleQuickQuestionTap(
    payload: ChatQuickQuestionSuggestionsPayload,
    item: ChatQuickQuestionSuggestionsPayload.Item
) async {
    do {
        try await sendMessageUseCase.execute(
            threadID: currentThreadID,
            input: item.text,
            quickQuestionContext: .init(
                batchID: payload.batchID,
                generatedQuestionID: item.id,
                level: item.level,
                contextPolicy: item.contextPolicy
            )
        )
    } catch {
        notificationClient.error(error.localizedDescription, title: L10n.text("common.error"))
    }
}
```

### 14.5 SparkService 生成服务示例

```python
class ChatQuickQuestionGenerationService:
    def generate_for_thread(self, *, user, thread_id, member_id, trigger, limit=3):
        thread = self._get_thread_for_user(user=user, thread_id=thread_id)
        self._assert_member_bound(thread=thread, member_id=member_id)

        revision = self._latest_message_revision(thread)
        existing = self._find_ready_batch(
            user=user,
            thread=thread,
            member_id=member_id,
            model_name=thread.current_model_name,
            trigger=trigger,
            source_message_revision=revision,
        )
        if existing:
            return existing

        context = self.context_builder.build(
            user=user,
            thread=thread,
            member_id=member_id,
            max_messages=20,
        )
        questions = self.model_client.generate_questions(
            model_name=thread.current_model_name,
            context=context,
            limit=limit,
        )
        batch = self.repository.create_batch(
            user=user,
            thread=thread,
            member_id=member_id,
            model_name=thread.current_model_name,
            trigger=trigger,
            source_message_revision=revision,
            questions=questions,
        )
        self.message_block_writer.write_quick_question_block(batch=batch)
        return batch
```

### 14.6 backoffice-web API client 示例

```ts
export interface QuickQuestionRow {
  id: number;
  code: string;
  text: string;
  category: string;
  status: 'draft' | 'enabled' | 'disabled' | 'expired';
  level: 1 | 2 | 3;
}

export function fetchQuickQuestions(params: Record<string, unknown>) {
  return http.get<unknown, { results: QuickQuestionRow[]; count: number }>(
    '/api/admin/v1/chat/quick-questions/',
    { params },
  );
}
```

### 14.7 测试用例建议

| 测试 | 断言 |
| --- | --- |
| `test_generate_uses_thread_model` | 生成服务使用 `ChatThread.current_model_name` |
| `test_generate_requires_bound_member` | thread 未绑定成员或成员不一致时拒绝生成 |
| `test_generate_is_idempotent` | 同一 revision 不重复创建 batch 和 block |
| `test_generated_block_sync_payload` | 写入的 block 能被 chat_sync 返回 |
| `test_client_decodes_quick_question_payload` | Swift payload 编解码成功 |
| `test_client_tap_sends_question` | 点击问题后发送对应用户消息 |

## 15. 隐私与合规要求

1. 未授权 Apple 健康时，不读取、不展示、不发送健康数据。
2. 健康数据卡片必须标识真实数据状态；使用示例数据时必须显示“示例数据”，且不得发送给 AI。
3. 发送给 AI 的健康摘要应遵循现有工具授权和模型出境授权策略。
4. 脂肪肝、血压异常等敏感推荐只作为“咨询入口”，不能暗示诊断。
5. AI 回复需保留健康建议免责声明，尤其是脂肪肝、血压、用药相关问题。
6. 生成日志需避免记录完整敏感指标；建议只记录 `reason_code`、问题 ID、场景、成员 ID 和脱敏摘要。

## 16. 验收标准

### 16.1 UI 验收

- 新建空 Chat 会话能看到健康数据卡片和服务端返回的快捷问题。
- 卡片样式参考附图：浅色背景、圆角容器、指标摘要、右侧操作入口。
- 服务端返回的问题完整显示，不被截断到不可读。
- 深色模式、动态字体、iPhone 小屏宽度下不重叠。
- 已有历史消息的会话不强行插入初始卡片。

### 16.2 数据验收

- 有真实体重、步数数据时展示真实值和更新时间。
- 无权限时展示授权/绑定引导或隐藏健康数据卡片。
- 无数据时不展示虚假数值。
- 切换成员后卡片和推荐问题同步刷新。
- SparkClient 不存在固定问题常量作为展示来源。
- 服务端推荐接口返回空列表时，客户端不展示旧问题。
- 绑定成员的会话进入后，生成问题保存到服务端并能通过消息块恢复展示。

### 16.3 交互验收

- 点击任一快捷问题后能创建/进入本会话并发送问题。
- 点击健康卡片“去解读”后，AI 能获得当前健康摘要上下文。
- 发送失败时沿用 Chat 现有失败消息/重试机制。
- 连续快速点击不会重复发送多条相同问题。
- 消息内生成问题点击后，原卡片不丢失；重新进入对话仍能看到该卡片。

### 16.4 推荐验收

- 命中减脂目标或体重信号时，服务端返回减脂类问题优先。
- 命中脂肪肝标签或报告信号时，服务端返回脂肪肝类问题优先。
- 命中体脂率/体重秤数据时，服务端返回体脂率类问题优先。
- 没有任何信号时，服务端返回后台配置的默认问题池。
- 后台停用问题后，推荐接口不再返回该问题。
- 对话绑定成员且存在最近消息时，优先返回或展示当前模型生成问题。
- 当前对话切换模型后，新生成批次记录新的 `model_name`。

### 16.5 服务端验收

- 新增快捷问题推荐接口。
- 新增快捷问题生成接口。
- 新增快捷问题数据模型和迁移。
- 新增生成批次和生成问题数据模型。
- 生成问题可写入 `chat_sync` 消息块并多端同步。
- 支持初始种子数据导入。

### 16.6 后台验收

- `backoffice-web` 显示 `对话 / 用户对话`、`对话 / 快捷问题配置`。
- 快捷问题配置页支持列表、筛选、新增、编辑、启用、停用、等级调整。
- 后台可查看模型生成的问题批次、使用模型、所属会话。
- RBAC 菜单权限、按钮权限、API 权限可控。
## 17. 风险与处理

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| 健康数据权限复杂 | 用户看到空卡片或误解数据来源 | 明确授权态、无数据态、示例态 |
| 个性化推荐过度医疗化 | 可能造成诊断暗示 | 只推荐问题，不输出结论；敏感问题需合规文案 |
| 服务端推荐接口失败 | 快捷问题不可用 | 客户端使用未过期服务端缓存；无缓存则隐藏快捷问题区域 |
| 进入对话频繁生成 | 消息流被重复卡片污染 | 用 `thread_id + member_id + message_window_hash + model_name` 做幂等 |
| 当前模型生成质量不稳定 | 推荐问题不准或重复 | 后台配置兜底问题池，生成记录可用于人工排查 |
| 卡片占据过多空间 | 影响 Chat 输入效率 | 空会话展示起始卡片；历史会话仅在助手消息内展示紧凑追问卡片 |
| 用户只想查看历史 | 插入新问题会打扰 | 进入已有会话不自动插入，只恢复已有卡片 |
| 多消息未收敛就生成 | 问题偏离真实意图 | 等 assistant 回复完成后基于完整窗口生成 |
| 后台菜单权限未配置 | 运营无法维护问题 | RBAC 初始化同步菜单、按钮、API 权限 |
| 健康摘要过长 | 增加 token 和隐私风险 | 只发送最小必要摘要，原始明细由工具按需读取 |

## 18. 分期建议

### v1 服务端生成 MVP

1. SparkService 新增快捷问题生成接口、推荐接口。
2. 空会话展示健康卡片和服务端默认/成员起始问题。
3. 已有会话不因进入页面立即生成；等待用户发送消息并收到 AI 回复后再判断是否生成。
4. 生成问题保存到服务器，并写入当前对话消息块。
5. SparkClient 渲染消息内快捷问题卡片，点击后直接发送对应问题。
6. 用户点击问题时直接创建普通用户消息，并在消息 metadata 中可选记录来源问题 ID。
7. 导入附图 3 个问题作为服务端兜底种子数据。
8. 加入基础降频：单 thread 每日最多 3 个生成 batch。

### v2 后台配置

1. `backoffice-web` 新增 `对话 / 快捷问题配置` 页面。
2. 支持问题新增、编辑、启停、等级配置。
3. 支持查看模型生成批次、生成问题、使用模型。
5. 接入 RBAC 权限和后台操作审计。

### v3 智能推荐

1. 结合最近会话、任务、健康趋势生成动态问题。
2. 支持 AI 生成候选问题，但必须经过模板白名单、规则约束或合规校验。
3. 根据人工审核优化提示词和等级配置。
4. 支持 A/B 测试不同问题池和展示等级。
5. 支持按成员长期画像优化问题类型，但只存储标签，不存储敏感原文。

## 19. 开放问题

1. 健康数据卡片首期是否只展示体重和步数，还是同时展示体脂率/血压/睡眠？
2. 点击快捷问题是“直接发送”还是“填入输入框等待用户确认”？本工单建议直接发送。
3. 脂肪肝问题是否必须在用户有相关报告/画像时才推荐，还是可由后台配置为默认问题池？
4. 健康卡片是否需要“展开”态展示更多指标，还是仅做跳转/解读入口？
5. 快捷问题相关代码在 `ai_config` 内是直接放入现有文件，还是拆成 `quick_question_*` 子文件？
6. 后台对话一级菜单目前如被隐藏，是否本期一并恢复展示？
7. 生成问题卡片是否由服务端直接创建 assistant 消息，还是作为现有 assistant 回复的附加 block？
8. “当前对话模型”是否完全沿用 thread 配置，还是允许后台为生成任务设置禁用名单？

## 20. 结论

本需求应改为“服务端生成 + 问题池兜底 + 低打扰触发”的架构：快捷问题不固定、不写死在 SparkClient。对话绑定成员时，不应在用户每次进入历史会话时立即插入新问题，而应在用户完成一轮或多条消息输入、AI 回复完成后，由 SparkService 使用当前对话模型、当前成员摘要和多消息窗口生成问题，生成结果保存到服务器并写入消息内卡片；未绑定成员或生成失败时，回退后台配置的问题池。

首期以“回复后生成问题 + 消息内展示 + 点击后直接发送”为 MVP；后台配置作为兜底和运营治理能力，与现有 `对话 / 用户对话` 并列新增 `对话 / 快捷问题配置`。生成问题需要保存到服务器并通过消息块同步，用户点击后只走正常 Chat 消息链路。
