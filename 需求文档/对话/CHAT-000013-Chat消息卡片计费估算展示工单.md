# CHAT-000013 Chat 消息卡片计费估算展示工单

## 背景

DeepTutor Web 会在助手消息底部展示 `cost · tokens · calls`。SparkClient 当前 Chat 消息卡片缺少费用感知，用户无法在单条助手回复下看到本轮模型调用的大致成本。

## 范围

- 在 `SparkClient/Projects/Features/Chat` 内实现本地估算。
- 在 Chat 助手消息卡片底部展示估算费用、估算 token 数和估算调用次数。
- 使用项目模型配置中的 `AIScenarioRemoteModelRow.priceTier`：
  - `0`：免费
  - `1`：经济
  - `2`：标准
  - `3`：高级
- 根据系统国家/地区展示货币：
  - 中国大陆：人民币 `¥`
  - 非中国大陆：美元 `$`

## 估算规则

客户端当前没有服务端真实 prompt/completion token usage，因此本工单只做 UI 估算，并尽量对齐 DeepTutor-main 的统计口径：

- prompt token：当前 assistant 消息之前的可见消息文本字符数 / `3.5`
- completion token：当前 assistant 消息内正文、思考过程、工具调用名、工具参数、工具结果字符数 / `3.5`
- total token：`prompt token + completion token`
- calls：无工具调用按 `1` 次；有工具调用按 `工具块数量 + 1` 估算，至少 `2` 次
- 价格：`estimatedTokens / 1000 * tierEstimatedUSDPer1K`
- 人民币：美元估算价 * `7.20`

价格分段按每千 token 的混合估算价定义：

| priceTier | 名称 | USD / 1K tokens |
| --- | --- | --- |
| 0 | 免费 | 0 |
| 1 | 经济 | 0.00030 |
| 2 | 标准 | 0.00500 |
| 3 | 高级 | 0.03000 |

## 验收

- 已完成的 assistant 消息卡片底部出现费用估算行。
- 中国地区显示 `¥`，其他地区显示 `$`。
- 模型未命中时默认按免费档展示，避免误报收费。
- 本功能不做真实扣费，不影响发送链路和同步链路。
