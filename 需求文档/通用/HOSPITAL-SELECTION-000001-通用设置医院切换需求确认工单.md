# HOSPITAL-SELECTION-000001 通用设置医院切换需求确认工单

> 工单状态：需求确认完成，待开发  
> 当前阶段：需求与落地方案已完成，不修改业务代码  
> 创建日期：2026-09-20  
> 适用系统：SparkClient iOS、SparkService `hospital_care`

## 1. 需求背景

当前服务端已经可以返回多家启用医院，iOS 端也已经具备医院首页、科室目录、医生智能体目录、挂号演示、线上问诊和医院会话能力。

但是客户端当前仍把“服务端医院列表第一家”作为默认演示医院。随着天长市中医院、天长市人民医院等多家医院进入同一套服务，患者无法在客户端明确选择医院；服务端排序变化也可能导致客户端自动切换到另一家医院。

本需求拟在 iOS“设置 → 通用”中增加医院切换选项，并持久化当前选择。切换后，医院首页、科室、医生智能体以及后续医院服务默认加载所选医院。

## 2. 用户目标与问题范围

- 用户可以在“设置 → 通用”查看当前医院并进入医院选择页面。
- 医院列表来自现有医院目录接口，不在客户端写死医院 UUID、编码或名称。
- 用户选择后持久化医院 ID。
- 重新启动 App 后继续加载上次选择的医院。
- 医院首页、医生智能体目录、挂号和线上问诊等医院入口统一使用当前选择。
- 医院切换不得修改历史会话原有的医院、医生智能体和知识库绑定。

## 3. 当前代码事实

### 3.1 通用设置

- `GeneralSettingsView` 位于：
  - `SparkClient/Projects/Features/Settings/GeneralSettings/Presentation/GeneralSettingsView.swift`
- 当前页面包含版本、首页样式、首页 AI 对话入口、首页饮食入口、医疗通知、识别重试和缓存设置。
- 当前页面没有医院选择 Section。
- 页面现有偏好通常由 `ObservableObject` Store 驱动，并使用 `UserDefaults` 持久化；例如 `HomeStylePreferenceStore`。

### 3.2 医院列表和当前医院解析

- `HospitalCareRemoteAPI.listHospitals(page:pageSize:)` 已调用：
  - `GET /api/v1/hospital-care/hospitals/`
- `HospitalSummary` 已包含：
  - `id`
  - `code`
  - `name`
  - `shortName`
  - `introduction`
  - `status`
- `HospitalCatalogMemoryCache` 已按 `accountID` 缓存医院列表，并支持 stale-while-revalidate 和 single-flight。
- `ResolveDemoHospitalUseCase` 当前固定取医院列表第一家：
  - 缓存命中时返回缓存数组第一项；
  - 远端请求成功时返回服务端数组第一项；
  - 列表为空或请求失败时返回 `missing/failed`。
- 当前没有“已选择医院”的持久化 Store。

### 3.3 当前医院的消费位置

以下页面或流程直接依赖 `ResolveDemoHospitalUseCase`：

- 医院首页 `HospitalHomeViewModel`
- 医生智能体目录 `HospitalAgentDirectoryViewModel`
- 医院会话列表入口 `ChatConversationListPage`
- 线上问诊流程 `ConsultFlowView`
- 科室/医生选择页
- 挂号演示页 `HospitalRegistrationDemoView`

因此切换医院不能只更新设置页面文字，必须修改统一医院解析源。

### 3.4 缓存事实

- 医院列表：账号级内存缓存。
- 科室和智能体目录：缓存键包含 `accountID + hospitalID`。
- 医院会话 scope、运行配置和医院知识库均已有医院/账号隔离。
- 当前医院选择本身尚未持久化。

## 4. 已知偏差与风险

- 继续取服务端第一家医院，会因为后台排序变化而静默切换医院。
- 如果医院偏好不按账号隔离，账号 A 的医院选择可能影响账号 B。
- 如果只修改医院首页，医生目录、挂号、问诊或聊天入口仍可能加载另一家医院。
- 切换医院时若复用旧页面状态，可能短暂展示上一家医院的科室或医生。
- 历史医院会话绑定的是原医院和原智能体，不能因默认医院变化而改写。
- 已保存医院被停用或删除时，需要明确回退规则。

## 5. 业务目标

1. 通用设置新增“当前医院”入口。
2. 医院选择页加载服务端启用医院列表。
3. 选择成功后写入本地持久化偏好。
4. 所有需要“默认医院”的新页面和新流程统一读取该偏好。
5. 切换后清理或失效当前页面状态，并按新医院重新加载科室和医生智能体。
6. 保留历史会话原绑定，不跨医院迁移或重写。

## 6. 页面/UI 原型概览

```text
设置 > 通用

┌──────────────────────────────────────┐
│ 医院服务                             │
├──────────────────────────────────────┤
│ 当前医院       天长市中医院       > │
└──────────────────────────────────────┘

点击后：

选择医院
┌──────────────────────────────────────┐
│ ✓ 天长市中医院                      │
│   三级中医医院                      │
├──────────────────────────────────────┤
│   天长市人民医院                    │
│   三级综合性医院                    │
└──────────────────────────────────────┘
```

完整加载态、空态、失败态、医院停用和切换规则见第 12、13、20 节。

## 7. 当前关键文件

```text
SparkClient/
├─ SparkClient/Projects/Features/Settings/GeneralSettings/Presentation/GeneralSettingsView.swift
├─ SparkClient/Projects/Features/Home/Presentation/HomeStylePreferenceStore.swift
├─ SparkClient/Projects/Features/HospitalCare/Domain/HospitalAgentCard.swift
├─ SparkClient/Projects/Features/HospitalCare/Infrastructure/HospitalCareDTO.swift
├─ SparkClient/Projects/Features/HospitalCare/Infrastructure/HospitalCareRemoteAPI.swift
├─ SparkClient/Projects/Features/HospitalCare/Infrastructure/HospitalCatalogMemoryCache.swift
├─ SparkClient/Projects/Features/HospitalCare/Application/ResolveDemoHospitalUseCase.swift
├─ SparkClient/Projects/Features/HospitalCare/Presentation/Home/HospitalHomeViewModel.swift
├─ SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift
├─ SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings
└─ SparkClient/Projects/App/Resources/en.lproj/Localizable.strings

SparkService/
└─ hospital_care 患者端医院列表、科室、智能体和会话接口
```

## 8. 当前非目标

- 本阶段不修改 Swift 或 Django 业务代码。
- 不允许用户修改医院资料。
- 不把历史会话迁移到新医院。
- 不根据医院名称或列表位置写死默认医院。
- 医院选择只在当前设备按账号本地持久化，本期不向服务端同步偏好。

## 9. 一问一答确认记录

### 第 1 问：医院选择应按什么范围持久化？

为什么要问：客户端存在账号切换和游客/正式账号场景。如果医院选择是设备全局值，后登录的账号会继承前一个账号的选择；如果按账号隔离，则每个账号可以恢复自己的医院上下文。

请选择：

- A. 按账号隔离持久化（推荐）  
  使用 `accountID + selectedHospitalID` 保存；切换账号后恢复该账号上次选择，未选择过的账号按默认规则初始化。
- B. 整台设备共用一个医院选择  
  实现简单，但账号切换会共享医院偏好，不符合现有医院缓存和会话的账号隔离方式。
- C. 仅内存保存，不跨启动持久化  
  退出 App 后丢失选择，与本需求“持久化存储”不一致。
- D. 同时保存设备默认值和账号覆盖值  
  可支持复杂继承，但首版需要额外优先级和清理规则，容易产生难以解释的医院切换行为。

请选择 A、B、C 或 D。

#### 第 1 问确认

**已确认选择 A：按账号隔离持久化。**

落地约束：

- 当前医院偏好必须以 `accountID + selectedHospitalID` 为作用域，不使用整台设备共享的单一医院 ID。
- 推荐存储键：`spark.hospital.selection.<accountID>`；值只保存服务端医院 UUID，不复制医院名称、科室或医生数据。
- 同一账号重新启动 App、重新进入医院模块或重新登录后，恢复该账号上次有效选择。
- 切换账号时，停止消费前一账号的当前医院偏好，重新读取新账号对应的医院 ID。
- 新账号不得继承其他账号的医院选择。
- 医院列表、科室、智能体目录仍按现有 `accountID + hospitalID` 缓存键隔离。
- 登出是否删除医院选择暂不在本题决定；应与账号其他持久偏好的保留策略一起在后续问题确认。

### 第 2 问：账号从未选择医院，或已保存医院已经停用/不存在时，默认加载哪家医院？

为什么要问：持久化值并不一定永久有效。新账号没有保存值，医院也可能被停用或从服务端列表移除。必须明确回退规则，避免医院首页空白、继续使用无效缓存，或因为列表排序变化产生无法解释的选择。

请选择：

- A. 使用服务端当前返回的第一家启用医院，并立即持久化（推荐）  
  延续当前默认行为，但首次解析后把结果固定到该账号；后续服务端排序变化不会再自动切换医院。
- B. 必须进入设置手动选择，未选择前医院模块不可用  
  选择最明确，但首次使用路径被阻断，用户无法直接进入医院首页或院内名医。
- C. 优先匹配固定医院编码，匹配不到再取第一家  
  适合单医院演示，但会把部署环境和具体医院写死在客户端需求中。
- D. 只恢复旧医院；失效后保持错误状态并要求用户重新选择  
  不会静默切换，但医院停用后所有默认医院入口都会进入阻断状态。

请选择 A、B、C 或 D。

#### 第 2 问确认

**已确认选择 A：使用服务端第一家启用医院并立即持久化。**

落地约束：

- 账号没有已选医院记录时，请求现有医院列表接口，并按服务端返回顺序选择第一家可用医院。
- 首次解析成功后立即把医院 UUID 写入当前账号的医院偏好，后续启动不再因为服务端排序变化自动切换。
- 已持久化医院仍在启用列表中时，始终优先使用该医院，不重新取第一家。
- 已持久化医院被停用、删除或不再出现在当前账号可见医院列表中时，视为选择失效。
- 选择失效后移除旧医院 ID，回退到服务端第一家启用医院，并立即写入新的医院 ID。
- 医院列表为空时不得保留一个不可用的“当前医院”；医院模块进入无可用医院状态，普通健康和普通对话功能不受影响。
- 医院列表请求失败但本地医院目录缓存仍包含已选医院时，可以继续展示缓存医院；是否允许继续发起医院业务请求由后续异常问题确认。

### 第 3 问：用户在医院选择页点击另一家医院后，何时正式切换？

为什么要问：医院切换会刷新首页、科室、医生智能体和后续新咨询的默认医院。如果点击即切换，路径最短；如果还需要确认按钮或二次确认，则能避免误触，但增加一步操作。

请选择：

- A. 点击医院行后立即保存并切换，然后自动返回通用设置（推荐）  
  符合系统设置类单选项习惯；选中后写入医院 ID，返回时“当前医院”立即显示新值，医院模块下次进入加载新医院。
- B. 点击医院行只勾选，导航栏“完成”后才保存  
  可以反复比较后确认，但单选医院场景多一步操作。
- C. 点击医院行后弹出二次确认，确认后切换  
  能提示影响范围，但频繁切换时交互偏重。
- D. 在通用设置页面直接使用 Picker 切换，不进入独立选择页  
  页面简单，但医院名称、等级、加载态、失败态和未来搜索扩展空间有限。

请选择 A、B、C 或 D。

#### 第 3 问确认

**已确认选择 A：点击后立即保存、切换并返回通用设置。**

落地约束：

- 医院选择页采用单选列表；点击非当前医院行即发起切换，不再显示“完成”按钮或二次确认弹窗。
- 点击当前已选医院不重复写入、不触发刷新，可直接保持当前页面或返回，由 UI 实现采用系统默认导航行为。
- 切换操作先校验目标医院仍存在于本次已加载的启用医院列表，再写入当前账号的医院 UUID。
- 持久化成功后更新内存中的当前医院状态，并自动返回“通用”设置页面。
- “通用”页面的“当前医院”副标题立即显示新医院名称。
- 持久化或状态切换失败时不返回、不修改原医院，医院行恢复可点击并展示轻量错误提示。
- 快速连续点击时只接受第一个有效切换操作，提交期间禁用其他医院行，避免医院 ID 和页面状态错位。
- 本操作只改变后续默认医院上下文，不修改已有历史会话的 `hospitalID`、`agentID`、知识库 Manifest 或消息记录。

### 第 4 问：切换医院后，已经驻留在内存中的医院页面和目录数据如何处理？

为什么要问：医院 Tab、名医目录等页面可能仍保留上一家医院的 ViewModel 状态。如果只写入偏好而不通知这些页面，用户返回医院 Tab 时可能继续看到旧医院，直到手动刷新或重启 App。

请选择：

- A. 立即发布医院切换事件；可见页面自动清空旧状态并加载新医院，未显示页面下次进入加载（推荐）  
  当前医院全局一致；旧医院缓存按 `hospitalID` 保留供以后切回，但页面不继续展示旧数据。
- B. 只保存选择，所有医院页面下次重新创建时生效  
  实现较少，但常驻 Tab/ViewModel 可能长时间显示旧医院。
- C. 切换后清空全部医院缓存并重建所有医院页面  
  一致性强，但会丢弃其他医院仍可复用的目录缓存并增加网络请求。
- D. 切换后提示用户重启 App  
  实现最简单，但不符合正常设置项的即时生效预期。

请选择 A、B、C 或 D。

#### 第 4 问确认

**已确认选择 A：发布医院切换事件，可见页面立即加载新医院。**

落地约束：

- 医院切换成功后发布一次包含 `accountID`、旧医院 ID、新医院 ID 和切换版本号的事件。
- 当前可见且依赖默认医院的页面收到事件后，必须立即取消旧请求、清空上一家医院的页面态，并按新医院重新加载。
- 当前不可见的页面不抢占网络资源；下次出现时读取当前选择并加载新医院。
- 科室、医生智能体等旧医院缓存继续按 `accountID + hospitalID` 保留，切回时可复用，不执行全量缓存清除。
- 页面不得在切换期间继续展示旧医院名称、旧科室或旧医生列表；新数据未返回时显示加载态或骨架态。
- 晚到的旧医院网络响应必须因医院 ID 或切换版本不匹配而被丢弃，不能覆盖新医院页面。
- 历史会话仍按其自身保存的 `hospitalID` 和 `agentID` 打开，不受默认医院切换事件影响。

## 10. 最终确认结论

| 决策项 | 最终结论 |
| --- | --- |
| 持久化范围 | 按账号隔离，键中包含 `accountID`，值为医院 UUID |
| 首次默认值 | 服务端返回的第一家启用医院，解析后立即持久化 |
| 保存医院失效 | 删除失效值，回退第一家启用医院并重新持久化 |
| 选择交互 | 点击医院行立即保存、切换并返回“通用”设置 |
| 页面生效 | 发布切换事件；可见页面立即重载，隐藏页面下次进入重载 |
| 缓存处理 | 保留不同医院的隔离缓存，不清空全部医院缓存 |
| 历史数据 | 不修改历史会话、智能体、知识库 Manifest 和消息绑定 |
| 服务端改造 | 不新增接口，复用现有医院列表接口 |

## 11. 最终业务范围

### 11.1 本期必须实现

1. “设置 → 通用”新增“医院服务”Section，并显示当前医院。
2. 点击“当前医院”进入独立医院选择页。
3. 医院选择页通过现有 `GET /api/v1/hospital-care/hospitals/` 加载启用医院。
4. 当前医院按账号持久化；重新启动、退出后重新登录、切换账号后均读取对应账号的选择。
5. 新账号或选择失效时，自动选中服务端第一家启用医院并保存。
6. 点击另一家医院后立即提交；成功后返回“通用”页面。
7. 切换成功后通知医院首页、院内名医、挂号、线上问诊及医院默认入口刷新。
8. 所有默认医院消费者统一通过一个“当前医院解析”用例读取，不再自行取医院数组第一项。
9. 保留旧医院目录缓存；页面状态和在途请求必须切换到新医院。
10. 添加中英文文案、单元测试和页面状态测试。

### 11.2 明确不做

- 不允许客户端新增、编辑或删除医院。
- 不把医院选择同步到服务端账号资料。
- 不把默认医院变化回写到历史 Thread。
- 不迁移历史会话对应的医生智能体或知识库。
- 不清理旧医院的科室、医生、智能体详情缓存。
- 不在客户端写死天长市中医院、天长市人民医院的 ID、编码或名称。
- 不新增搜索、定位、按距离排序或常用医院能力。
- 不增加切换确认弹窗和“完成”按钮。

## 12. 信息架构与 Plain Text UI 原型

### 12.1 通用设置

```text
设置 > 通用

┌──────────────────────────────────────────┐
│ 医院服务                                 │
├──────────────────────────────────────────┤
│ 当前医院          天长市中医院        > │
└──────────────────────────────────────────┘

医院列表尚未解析：
┌──────────────────────────────────────────┐
│ 当前医院              正在加载…       > │
└──────────────────────────────────────────┘

无可用医院：
┌──────────────────────────────────────────┐
│ 当前医院              暂无可用医院     > │
└──────────────────────────────────────────┘
```

交互规则：

- Section 放在首页相关设置之后、医疗设置之前，避免与版本和缓存操作混在一起。
- 已解析当前医院时，右侧只显示医院 `shortName`；为空时回退 `name`。
- 当前医院正在初始化时允许进入医院选择页，选择页自行展示加载状态。
- 无可用医院或加载失败时仍允许进入选择页重试。

### 12.2 医院选择页

```text
< 通用                 选择医院

┌──────────────────────────────────────────┐
│ ✓  天长市中医院                          │
│    天长市中医院                          │
├──────────────────────────────────────────┤
│    天长市人民医院                        │
│    天长市人民医院                        │
└──────────────────────────────────────────┘

说明：切换医院后，医院首页、科室、医生和新咨询将使用新医院。
历史咨询记录不会改变。
```

- 行主标题使用 `name`；副标题优先展示非空 `shortName`，与主标题相同则展示 `introduction` 的单行摘要，仍为空时不占位。
- 当前医院行显示勾选标识。
- 点击当前医院：不写存储、不发事件、不发网络请求。
- 点击其他医院：立即进入提交态，锁定全部医院行；成功后自动返回。
- 提交态仅在被点击行显示轻量 `ProgressView`，不覆盖整页。

### 12.3 页面状态

| 状态 | 页面行为 |
| --- | --- |
| 首次加载且无缓存 | 显示 3～5 行骨架，不显示伪造医院 |
| 有账号级内存缓存 | 立即显示缓存列表，后台静默刷新 |
| 刷新成功 | 按服务端顺序替换列表并重新校验当前医院 |
| 刷新失败且有缓存 | 保留缓存，显示非阻断提示“当前显示上次加载结果” |
| 刷新失败且无缓存 | 显示错误说明和“重试”按钮 |
| 服务端列表为空 | 显示“暂无可用医院”，禁用切换 |
| 切换提交中 | 禁用全部行，目标行显示进度 |
| 切换失败 | 保留旧医院和当前页面，恢复点击并显示错误 |

## 13. 业务流程

### 13.1 App 启动或账号登录后的初始化

```text
账号进入已登录态
  ↓
取得 accountID
  ↓
读取 spark.hospital.selection.<accountID>
  ↓
读取账号级医院目录缓存；必要时请求医院列表
  ↓
过滤可用医院并校验已保存 hospitalID
  ├─ 保存值有效 → 解析为当前医院
  ├─ 保存值无效 → 选择第一家启用医院 → 覆盖保存
  ├─ 无保存值     → 选择第一家启用医院 → 首次保存
  └─ 无可用医院   → 清除失效保存值 → 返回 missing
```

- 初始化产生的首次默认选择不应被视为用户主动切换；没有旧医院时不要求刷新一遍尚未建立的页面。
- 若页面已经以其他医院运行，而刷新后发现该医院失效，则回退产生真实切换事件。
- 医院列表请求失败但内存缓存可解析当前医院时，继续使用缓存并标记 stale。
- 冷启动无缓存且请求失败时返回 `failed`，不得仅凭已保存 UUID 构造一个缺少服务端资料的 `HospitalSummary`。

### 13.2 用户主动切换

```text
点击非当前医院
  ↓
HospitalSelectionViewModel.select(hospital)
  ↓
校验账号未变化、医院仍在当前启用列表、当前没有提交任务
  ↓
写入账号级 UserDefaults
  ↓
更新内存 currentHospitalID / revision
  ↓
发布 hospitalSelectionDidChange
  ↓
自动返回“通用”设置
  ↓
可见医院页面取消旧任务、清空页面态、加载新医院
```

事务边界：只有本地持久化和内存状态都成功后才发布事件。任何失败都保留旧选择，不允许页面先切换后回滚。

### 13.3 可见页面刷新

```text
收到切换事件
  ↓
校验 event.accountID == 当前登录 accountID
  ↓
递增/记录 selectionRevision，取消旧 Task
  ↓
清空旧 hospital、departments、agents、筛选条件和错误态
  ↓
按 event.newHospitalID 解析新 HospitalSummary
  ↓
优先读取 accountID + newHospitalID 缓存
  ↓
后台请求最新科室和智能体目录
  ↓
请求返回时再次校验 hospitalID + revision
  ├─ 一致 → 更新页面
  └─ 不一致 → 丢弃晚到结果
```

刷新时应重置科室筛选，因为上一家医院的 `departmentID` 对新医院无意义；医生搜索词可以保留，但建议本期一并清空，以免用户误以为新医院没有医生。

### 13.4 隐藏页面刷新

- 隐藏页面可以只记录“当前选择已变化”，不立即发网络请求。
- 页面下次 `onAppear` 时比较已加载医院 ID 和 Selection Store 当前医院 ID。
- 二者不同则清空旧页面态并加载；相同则按原 stale-while-revalidate 逻辑处理。
- `hasLoadedOnce` 不能成为阻止医院切换后重载的永久门禁。

### 13.5 历史会话与显式医院上下文

医院解析优先级必须是：

1. 历史会话、深链或业务路由显式携带的 `hospitalID`；
2. 当前账号选择的默认医院；
3. 首次回退的第一家启用医院。

因此：

- 打开旧医院的历史会话时继续使用 Thread 绑定医院，不跳转到当前默认医院。
- 从医院首页、院内名医或挂号入口新建业务时使用当前默认医院。
- 医生智能体会话的知识库 Manifest 继续由会话实际绑定的智能体决定。

## 14. 状态与数据模型设计

### 14.1 持久化键

```text
key   = spark.hospital.selection.<accountID>
value = <hospital UUID string>
```

- 不保存医院名称、排序、科室或医生数据。
- UUID 无法解析时视为损坏值并删除。
- 退出登录保留该账号选择，以满足再次登录恢复；账号删除/彻底清除本地数据时再由统一账号清理流程删除。
- 设备账号同样使用其稳定 `accountID`，不得使用空字符串、游客公共键或当前成员 ID。

### 14.2 内存状态

建议新增：

```swift
struct HospitalSelectionSnapshot: Equatable, Sendable {
    let accountID: Int64
    let hospitalID: UUID?
    let revision: UInt64
}
```

`revision` 每次有效切换递增，用于拒绝旧请求回写；不需要持久化，进程启动后从 0 开始即可。

### 14.3 事件载荷

```swift
struct HospitalSelectionChange: Equatable, Sendable {
    let accountID: Int64
    let oldHospitalID: UUID?
    let newHospitalID: UUID
    let revision: UInt64
    let source: Source

    enum Source: String, Sendable {
        case user
        case initialFallback
        case invalidSelectionFallback
    }
}
```

- 用户主动切换和“原医院失效后的自动回退”需要通知页面。
- 首次初始化且 `oldHospitalID == nil` 时可以更新 Store，不必把事件广播为页面切换。
- 事件对象不传完整医院 DTO，消费者通过目录缓存或当前医院解析用例取得事实数据。

## 15. 客户端架构方案

### 15.1 新增组件

建议在 `HospitalCare` 域内新增：

```text
SparkClient/Projects/Features/HospitalCare/
├─ Application/
│  ├─ ResolveCurrentHospitalUseCase.swift
│  └─ SelectHospitalUseCase.swift
├─ Infrastructure/
│  └─ HospitalSelectionStore.swift
└─ Presentation/Selection/
   ├─ HospitalSelectionView.swift
   └─ HospitalSelectionViewModel.swift
```

职责：

- `HospitalSelectionStore`：按账号读写 UUID、维护内存快照并发布变更。
- `ResolveCurrentHospitalUseCase`：联合医院目录和选择 Store，完成有效性校验与第一家回退。
- `SelectHospitalUseCase`：处理用户主动切换的校验、写入和事件发布。
- `HospitalSelectionViewModel`：管理列表、加载/错误/提交状态，不自行拼装网络请求。
- `HospitalSelectionView`：只展示状态和触发选择。

### 15.2 现有组件调整

- `ResolveDemoHospitalUseCase`：当前名称和“永远第一家”的语义已不成立。建议由 `ResolveCurrentHospitalUseCase` 替代；若为控制改动暂保留类型名，其内部也必须改为选择优先，后续再完成命名迁移。
- `HospitalCareFeatureDependencies`：增加 `selectionStore`、`resolveCurrentHospital`、`selectHospital` 和 `makeHospitalSelectionViewModel`。
- `HospitalCareAssembly`：创建并注入同一个账号级 `HospitalSelectionStore` 实例。
- `AppContainer`：持有稳定 Store，不能在 SwiftUI `body` 或页面跳转时重复创建。
- `SettingsView` / `GeneralSettingsView`：注入 `session.accountID` 和医院依赖，新增医院入口。
- 所有现有 `resolveDemoHospital.execute` 调用改为当前医院解析入口。

### 15.3 为什么不把选择直接放进 `GeneralSettingsView`

- 医院首页、聊天列表、挂号和问诊都需要读取同一个状态。
- View 内 `@AppStorage` 无法自然表达账号作用域和医院有效性校验。
- 页面切换、账号切换、后台刷新和请求竞态需要集中管理。
- 单独 Store 更容易注入测试用 `UserDefaults(suiteName:)`，避免污染真实偏好。

## 16. 服务端接口契约

本需求不新增服务端接口，复用：

```http
GET /api/v1/hospital-care/hospitals/?page=1&page_size=100
Authorization: Bearer <token>
```

客户端依赖字段：

| 字段 | 用途 |
| --- | --- |
| `id` | 持久化值、后续科室/智能体接口路径参数 |
| `code` | 仅展示或诊断，不作为客户端默认选择规则 |
| `name` | 医院列表主标题 |
| `short_name` | 通用设置摘要和列表副标题 |
| `introduction` | 副标题缺失时的简介摘要 |
| `status` | 防御性过滤启用医院 |

契约要求：

- 服务端继续按后台配置顺序返回医院；客户端首次默认取过滤后的第一家。
- 客户端只把状态归一化后等于 `active` 的医院作为可选项；如果现有接口已只返回启用医院，此过滤仍保留为防御措施。
- 医院停用后应从列表移除或返回非 `active` 状态，客户端下次刷新执行失效回退。
- 401/403 交由现有登录与鉴权流程处理；医院选择页不吞掉账号失效。

## 17. 核心代码示例（设计参考，不是本次代码改动）

### 17.1 账号级选择 Store

```swift
import Combine
import Foundation

@MainActor
final class HospitalSelectionStore: ObservableObject {
    @Published private(set) var snapshot: HospitalSelectionSnapshot?

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var revision: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    func selectedHospitalID(accountID: Int64) -> UUID? {
        guard let raw = defaults.string(forKey: key(accountID)),
              let id = UUID(uuidString: raw) else {
            defaults.removeObject(forKey: key(accountID))
            return nil
        }
        return id
    }

    @discardableResult
    func select(
        _ hospitalID: UUID,
        accountID: Int64,
        source: HospitalSelectionChange.Source
    ) -> HospitalSelectionChange? {
        let oldID = selectedHospitalID(accountID: accountID)
        guard oldID != hospitalID else { return nil }

        defaults.set(hospitalID.uuidString, forKey: key(accountID))
        revision &+= 1
        let change = HospitalSelectionChange(
            accountID: accountID,
            oldHospitalID: oldID,
            newHospitalID: hospitalID,
            revision: revision,
            source: source
        )
        snapshot = .init(
            accountID: accountID,
            hospitalID: hospitalID,
            revision: revision
        )
        notificationCenter.post(
            name: .hospitalSelectionDidChange,
            object: change
        )
        return change
    }

    func removeInvalidSelection(accountID: Int64) {
        defaults.removeObject(forKey: key(accountID))
    }

    private func key(_ accountID: Int64) -> String {
        "spark.hospital.selection.\(accountID)"
    }
}

nonisolated extension Notification.Name {
    static let hospitalSelectionDidChange = Notification.Name(
        "SparkClient.hospitalSelectionDidChange"
    )
}
```

实际实现应把“首次初始化不广播”和“失效回退需要广播”的差异放在明确 API 中，避免调用方靠 `source` 猜测。

### 17.2 当前医院解析

```swift
struct ResolveCurrentHospitalUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let selectionStore: HospitalSelectionStore

    @MainActor
    func execute(
        accountID: Int64,
        forceRefresh: Bool = false
    ) async -> DemoHospitalResolution {
        do {
            let hospitals = try await loadHospitals(
                accountID: accountID,
                forceRefresh: forceRefresh
            )
            let active = hospitals.filter {
                $0.status.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "active"
            }
            guard let fallback = active.first else {
                selectionStore.removeInvalidSelection(accountID: accountID)
                return .missing
            }

            if let selectedID = selectionStore.selectedHospitalID(accountID: accountID),
               let selected = active.first(where: { $0.id == selectedID }) {
                return .resolved(selected)
            }

            selectionStore.select(
                fallback.id,
                accountID: accountID,
                source: .invalidSelectionFallback
            )
            return .resolved(fallback)
        } catch {
            // 与现有策略一致：优先尝试账号级目录缓存，再返回 failed。
            return .failed
        }
    }
}
```

生产实现必须复用 `HospitalCatalogMemoryCache.singleFlightHospitals`，不能另建第二套医院列表缓存。

### 17.3 医院选择 ViewModel

```swift
@MainActor
final class HospitalSelectionViewModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case ready
        case empty
        case failed(String)
    }

    @Published private(set) var hospitals: [HospitalSummary] = []
    @Published private(set) var selectedHospitalID: UUID?
    @Published private(set) var submittingHospitalID: UUID?
    @Published private(set) var loadState: LoadState = .loading

    let accountID: Int64
    let dependencies: HospitalCareFeatureDependencies

    func select(_ hospital: HospitalSummary) async -> Bool {
        guard submittingHospitalID == nil,
              hospital.id != selectedHospitalID,
              hospitals.contains(where: { $0.id == hospital.id }) else {
            return false
        }
        submittingHospitalID = hospital.id
        defer { submittingHospitalID = nil }

        do {
            try dependencies.selectHospital.execute(
                hospitalID: hospital.id,
                accountID: accountID
            )
            selectedHospitalID = hospital.id
            return true
        } catch {
            // 映射为页面轻量错误；不修改 selectedHospitalID。
            return false
        }
    }
}
```

### 17.4 设置入口与自动返回

```swift
private var hospitalSection: some View {
    Section(L10n.text("settings.general.hospital.section")) {
        MainNavigationLink {
            HospitalSelectionView(viewModel: hospitalSelectionViewModel)
        } label: {
            HStack {
                Text(L10n.text("settings.general.hospital.current"))
                Spacer()
                Text(hospitalSelectionViewModel.currentHospitalDisplayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
```

```swift
struct HospitalSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: HospitalSelectionViewModel

    var body: some View {
        List(viewModel.hospitals) { hospital in
            Button {
                Task {
                    if await viewModel.select(hospital) {
                        dismiss()
                    }
                }
            } label: {
                HospitalSelectionRow(
                    hospital: hospital,
                    isSelected: hospital.id == viewModel.selectedHospitalID,
                    isSubmitting: hospital.id == viewModel.submittingHospitalID
                )
            }
            .disabled(viewModel.submittingHospitalID != nil)
        }
        .navigationTitle(L10n.text("settings.general.hospital.select"))
        .task { await viewModel.load() }
    }
}
```

### 17.5 可见页面处理切换事件

```swift
func handleHospitalSelectionChange(_ change: HospitalSelectionChange) async {
    guard change.accountID == accountID else { return }

    activeLoadTask?.cancel()
    loadedSelectionRevision = change.revision
    hospital = nil
    departments = []
    agentCards = []
    selectedDepartmentID = nil
    loadState = .loading

    await loadSelectedHospital(
        hospitalID: change.newHospitalID,
        expectedRevision: change.revision
    )
}
```

每次异步返回前必须检查：

```swift
guard expectedRevision == selectionStore.snapshot?.revision,
      loadedHospitalID == selectionStore.snapshot?.hospitalID else {
    return
}
```

仅依赖 `Task.cancel()` 不足够，因为底层网络请求可能无法立即取消，必须同时做版本校验。

## 18. 关键文件改造清单

| 文件 | 计划改造 |
| --- | --- |
| `Features/Settings/GeneralSettings/Presentation/GeneralSettingsView.swift` | 增加医院 Section、当前医院摘要和选择页入口 |
| `Features/Settings/Presentation/SettingsView.swift` | 向通用设置传入账号 ID 和医院选择依赖 |
| `Features/HospitalCare/Infrastructure/HospitalSelectionStore.swift` | 新建账号级 UUID 持久化、内存快照和切换事件 |
| `Features/HospitalCare/Application/ResolveCurrentHospitalUseCase.swift` | 新建选择优先、第一家回退的统一解析逻辑 |
| `Features/HospitalCare/Application/SelectHospitalUseCase.swift` | 新建用户主动切换用例 |
| `Features/HospitalCare/Presentation/Selection/HospitalSelectionViewModel.swift` | 新建列表、选中、提交和错误状态 |
| `Features/HospitalCare/Presentation/Selection/HospitalSelectionView.swift` | 新建医院选择页面 |
| `Features/HospitalCare/Application/HospitalCareFeatureDependencies.swift` | 暴露选择 Store、用例和 ViewModel 工厂 |
| `App/Sources/App/Architecture/FeatureAssemblies.swift` | 装配并注入稳定选择实例 |
| `App/Sources/App/AppContainer.swift` | 持有账号生命周期内稳定的选择 Store |
| `Features/HospitalCare/Presentation/Home/HospitalHomeViewModel.swift` | 不再从缓存取 `.first`；监听切换并处理竞态 |
| `Features/HospitalCare/Presentation/HospitalAgentDirectoryViewModel.swift` | 监听切换，重置科室/搜索并加载新目录 |
| `Features/HospitalCare/Presentation/Registration/HospitalRegistrationDemoView.swift` | 入口改为当前医院解析 |
| `Features/HospitalCare/Presentation/Consultation/ConsultFlowView.swift` | 入口改为当前医院解析 |
| `Features/HospitalCare/Presentation/Consultation/ConsultDoctorSelectView.swift` | 保留显式 hospitalID 优先，不回退为任意第一家 |
| `Features/Chat/Presentation/ChatConversationListPage.swift` | 院内名医可用性探测与目录按当前医院刷新 |
| `App/Resources/zh-Hans.lproj/Localizable.strings` | 增加中文医院设置文案 |
| `App/Resources/en.lproj/Localizable.strings` | 增加对应英文文案 |

需要删除的旧假设：

- `HospitalHomeViewModel.load()` 中 `catalogCache.hospitals(accountID:)?.first`。
- `ResolveDemoHospitalUseCase.resolveFirst` 作为所有入口默认医院的唯一逻辑。
- 注释和状态名中的“演示医院”“第一家医院”等过时语义。

## 19. 各消费页面的具体行为

| 消费方 | 切换后的行为 |
| --- | --- |
| 医院首页 | 清空旧医院页面态，加载新医院基础信息、科室和精选医生 |
| 院内名医目录 | 清空旧科室筛选、医生列表和打开中状态，加载新医院目录 |
| 对话列表“院内名医”分段 | 保持在该分段并刷新为新医院医生；无医生时显示新医院空态 |
| 挂号 | 未提交流程立即重置为新医院；已进入具体预约确认页不在中途偷换医院 |
| 线上问诊 | 未提交入口切换到新医院；已填写但未提交表单如仍在前台，应提示医院已切换并重置医院相关选择 |
| 科室/医生选择页 | 显式 hospitalID 页面保持原上下文；默认入口重新创建时取当前医院 |
| 历史医院会话 | 完全保持 Thread 自身医院和智能体绑定 |
| 普通 AI 对话 | 不受影响 |
| 医院知识库本地缓存 | 不清理；仅进入具体智能体会话时按会话 Manifest 使用 |

对于挂号和问诊的“流程中状态”，不得静默把已选择的科室/医生组合到另一家医院。若事件发生时页面仍可见，应清空表单中的医院派生字段并给出“医院已切换，请重新选择科室和医生”。

## 20. 并发、一致性与异常边界

### 20.1 连续点击

- `submittingHospitalID != nil` 时禁用所有医院行。
- 不排队第二次选择，不执行最后点击覆盖。
- 第一次完成后页面已返回，用户如需再次切换需重新进入。

### 20.2 账号切换竞态

- 选择操作开始时捕获 `accountID`。
- 保存前再次确认当前登录账号未变化。
- 如果账号已切换，取消操作且不得写入新旧任一账号错误的键。
- 页面收到其他账号的选择事件时直接忽略。

### 20.3 目录刷新竞态

- 每次切换以 `revision` 标识页面加载世代。
- 旧请求结果即使成功也不能写回新医院页面。
- `HospitalCatalogMemoryCache` 可正常保存旧医院响应，因为其键包含医院 ID；禁止的只是旧响应写入当前页面展示态。

### 20.4 医院停用

- 当前医院仍在本地缓存但服务端最新列表标记为非启用时，不能继续作为新业务默认医院。
- 自动选择最新启用列表第一家并持久化。
- 如果没有启用医院，清除当前选择并进入 `missing`。
- 历史会话仍可按服务端权限读取；是否可继续发送由会话接口决定。

### 20.5 网络失败

- 有账号级医院目录缓存：继续展示缓存选择，标记为上次数据。
- 无缓存：通用设置显示加载失败，医院选择页提供重试。
- 切换本身是本地事务，不额外请求服务端；但目标必须来自本次已加载的有效列表。
- 切换后新医院业务请求失败时展示新医院的失败态，不允许恢复展示旧医院页面以假装成功。

### 20.6 数据损坏

- UserDefaults 值不是合法 UUID：删除后走首次默认规则。
- UUID 合法但不在启用列表：视为失效选择。
- 医院名称为空属于服务端契约异常；选择页显示通用占位“未命名医院”，日志记录 ID，不阻断 ID 校验。

## 21. 埋点与日志建议

不得记录 Token、患者资料或会话内容。建议记录：

```text
hospital.selection.resolve
  account_id_hash, source=persisted|first_active|cache, hospital_id, result

hospital.selection.change
  account_id_hash, old_hospital_id, new_hospital_id, source=user|fallback, result

hospital.selection.consumer_reload
  consumer=home|agent_directory|registration|consultation|chat, hospital_id, revision, result

hospital.selection.stale_response_dropped
  consumer, response_hospital_id, current_hospital_id, response_revision, current_revision
```

`accountID` 如现有日志规范禁止明文，应使用既有脱敏方式；医院 ID 可用于联调，但不要附带医疗或患者上下文。

## 22. 测试方案

### 22.1 Store 单元测试

建议新增：

```text
SparkClient/Tests/HospitalCare/HospitalSelectionStoreTests.swift
```

覆盖：

1. 账号 A/B 使用不同存储键，互不继承。
2. 合法 UUID 可跨 Store 重建恢复。
3. 非法 UUID 被删除并返回 nil。
4. 重复选择同一医院不增加 revision、不发事件。
5. 切换医院只发一次事件，载荷 old/new/account/revision 正确。
6. 登出不主动删除偏好；重新登录恢复。

### 22.2 当前医院解析测试

建议新增：

```text
SparkClient/Tests/HospitalCare/ResolveCurrentHospitalUseCaseTests.swift
```

覆盖：

1. 有效持久化选择不受服务端排序变化影响。
2. 无选择时取第一家 `active` 医院并保存。
3. 已选医院停用时回退第一家 active 并保存。
4. 已选医院删除时回退。
5. 列表全部停用时返回 missing 并清除失效值。
6. 网络失败但有缓存时解析缓存选择。
7. 网络失败且无缓存时返回 failed。
8. 后台刷新不把第一家覆盖到仍有效的用户选择。

### 22.3 医院选择 ViewModel 测试

覆盖：

1. 缓存先展示、后台刷新成功替换。
2. 点击当前医院不提交。
3. 点击新医院时进入提交态，成功后返回 true。
4. 提交中第二次点击被忽略。
5. 提交失败保留旧选中项并返回 false。
6. 无医院显示 empty。

### 22.4 消费页面测试

扩充现有：

```text
SparkClient/Tests/HospitalCare/HospitalHomeViewModelTests.swift
```

并新增目录切换测试，覆盖：

1. 收到当前账号事件后清空旧医院页面态。
2. 收到其他账号事件不处理。
3. 新医院缓存立即展示，随后刷新。
4. 旧医院慢请求晚到时不覆盖新医院。
5. 切换后科室筛选归零。
6. 隐藏页面下次出现时识别医院已变化。

### 22.5 手工验收矩阵

| 场景 | 预期 |
| --- | --- |
| 新账号首次进入 | 自动选择第一家启用医院并持久化 |
| 重启 App | 恢复该账号上次医院 |
| A 账号选中医院 1，B 账号选中医院 2 | 来回切换账号分别恢复 1、2 |
| 后台调整医院排序 | 已有有效选择不变化 |
| 点击另一家医院 | 立即切换并返回通用设置 |
| 切换时快速连点 | 只执行第一次有效操作 |
| 返回医院首页 | 不出现旧医院名称、科室和医生混合 |
| 旧请求晚到 | 页面仍保持新医院数据 |
| 切回旧医院 | 可复用旧医院隔离缓存并后台刷新 |
| 已选医院停用 | 自动回退新的第一家启用医院 |
| 无可用医院 | 医院模块空态，普通功能正常 |
| 打开旧医院历史会话 | 仍使用旧 Thread 的医院和智能体 |
| 从新医院创建咨询 | 新 Thread 绑定新医院及其医生智能体 |

## 23. 验收标准

- [ ] “通用”设置可查看当前医院并进入医院选择页。
- [ ] 医院数据完全来自现有服务端接口，无硬编码医院。
- [ ] 选择按 `accountID` 隔离并跨启动恢复。
- [ ] 新账号自动保存第一家启用医院。
- [ ] 有效已选医院不被服务端排序变化覆盖。
- [ ] 失效选择按规则回退并重新保存。
- [ ] 点击医院即切换，成功自动返回，失败不改变旧医院。
- [ ] 切换事件仅发一次且作用于当前账号。
- [ ] 可见医院页面立即进入新医院加载态。
- [ ] 隐藏页面下次进入使用新医院。
- [ ] 旧医院缓存保留，且不会作为新医院页面数据展示。
- [ ] 晚到请求不能覆盖当前医院页面。
- [ ] 所有默认医院消费点不再直接取列表 `.first`。
- [ ] 历史会话和知识库绑定不被改写。
- [ ] 中英文文案、VoiceOver 标签、加载/空/失败状态齐全。
- [ ] 新增测试通过，现有 HospitalCare、Chat 和 Settings 相关测试无回归。

## 24. 推荐实施顺序

1. 新增 `HospitalSelectionStore`、快照和切换事件，先完成 Store 测试。
2. 新增 `ResolveCurrentHospitalUseCase`，迁移第一家回退逻辑并完成解析测试。
3. 在 `AppContainer`、`HospitalCareAssembly` 和依赖 Facade 中注入稳定实例。
4. 替换所有默认医院消费点，优先消除直接 `.first`。
5. 为医院首页和名医目录增加事件处理、任务取消及 revision 防竞态。
6. 增加医院选择 ViewModel/View，并接入通用设置。
7. 处理挂号、问诊和聊天入口的切换边界。
8. 补齐本地化、无障碍、日志与错误态。
9. 执行单元测试、手工矩阵和双账号切换验收。

## 25. 开发拆分建议

### 子任务 A：选择基础设施

- Store、存储键、事件、解析用例、依赖注入。
- 完成后即使没有 UI，现有医院入口也应能稳定恢复账号选择。

### 子任务 B：设置 UI

- 通用设置入口、医院选择页、加载/空/错误/提交状态。
- 自动返回与防连续点击。

### 子任务 C：消费者切换

- 医院首页、院内名医、聊天探测、挂号、问诊。
- 重点验收旧请求晚到与流程中医院切换。

### 子任务 D：测试与收尾

- 单元测试、集成测试、本地化、无障碍和日志。
- 清理“演示医院/第一家医院”的过时命名和注释。

## 26. 最终交付说明

本工单已经完成问答确认和落地设计，可以进入开发。实现时以本文件第 10～25 节为最终基线；第 9 节保留决策过程，便于追溯“为什么这样设计”。本次文档整理未修改任何 Swift、Django、数据库或配置代码。
