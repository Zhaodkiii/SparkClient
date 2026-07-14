# MEDICINE-CABINET-ARCHIVE-REFRESH-000001 药品归档后家庭药箱列表数量未更新问题工单

## 1. 工单摘要

| 项目 | 内容 |
|---|---|
| 工单名称 | 药品归档后家庭药箱列表数量未更新 |
| 影响端 | SparkClient |
| 影响页面 | 家庭药箱 / 个人药箱药品列表、药品详情 |
| 影响资源 | `medicine-boxes` |
| 优先级 | P1 |
| 当前状态 | 待修复 |

## 2. 问题现象

用户在家庭药箱中归档药品后，服务端数据已经正确更新，刷新接口也已经返回少一条数据，但客户端列表内展示的药品数量没有及时更新。

从日志看，归档前家庭药箱汇总接口返回 2 条药品：

```text
GET /api/v1/medical/medicine-cabinet/summary?member_id=450
data=[id=146,is_archived=false, id=145,is_archived=false]
```

归档药品 `id=145` 后，服务端 PATCH 成功：

```text
PATCH /api/v1/medical/resources/145?kind=medicine-boxes
body={"is_archived":true}
response.data.id=145
response.data.is_archived=true
```

随后刷新家庭药箱汇总接口，服务端已只返回 1 条：

```text
GET /api/v1/medical/medicine-cabinet/summary?member_id=450
data=[id=146,is_archived=false]
```

但客户端列表数量仍未正确同步。

## 3. 初步结论

服务端数据是正确的，问题集中在客户端归档成功后的本地状态回写。

当前归档成功后，`MedicineBoxDetailPage` 会先调用 `onSaved(updated)`。家庭药箱页收到后走 `handleBoxSaved`，该方法会执行 `viewModel.upsert(box)`，把已经归档的药品继续写回 active 列表和首页缓存。

日志中的这一行可以印证该路径：

```text
家庭药箱回写首页完整成员数据缓存 entryMemberID=450 count=2
```

这里的 `count=2` 发生在归档 PATCH 成功之后，说明归档后的 `id=145` 仍被作为普通保存结果回写到了家庭药箱缓存。

### 3.1 新增日志线索：刷新后没有出现 family 缓存回写日志

补充现象：

```text
GET /api/v1/medical/medicine-cabinet/summary?member_id=450
response.data.count=1
```

接口已经返回 1 条，但没有出现以下日志：

```text
家庭药箱回写首页完整成员数据缓存 entryMemberID=450 count=1
```

结合代码判断，这并不一定表示 `reloadAndNotifyParent()` 没有执行。`notifyParentCompleteDataIfFamily()` 内部有两个 guard：

```swift
guard mode == .family else { return }
guard var completeData = memberCompleteData else { return }
```

如果当前药箱页是从用药列表、用药执行中心或服药记录 Sheet 进入的 `.personal` 模式，第一个 guard 会直接返回，因此不会打印 family 缓存回写日志。

当前已确认 `.personal` 入口包括：

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationsListPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionCenterPage.swift
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicationExecutionCenter/MedicationExecutionLogSheet.swift
```

这些入口创建 `FamilyMedicineCabinetPage` 时使用：

```swift
mode: .personal
onMedicineBoxesChanged: ...
```

因此本问题需要同时检查两条回写链路：

1. `.family` 模式：`notifyParentCompleteDataIfFamily()` -> `completeData.familyMedicineBoxes`
2. `.personal` 模式：`notifyParentIfPersonal()` -> `onMedicineBoxesChanged`

## 4. 涉及文件

### 4.1 家庭药箱页面

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/FamilyMedicineCabinetPage.swift
```

关键位置：

1. `MedicineBoxGridView(...)` 调用处。
2. `handleBoxSaved(_:)`。
3. `handleBoxDeleted(id:)`。
4. `notifyParentCompleteDataIfFamily()`。
5. `reloadAndNotifyParent()`。

当前 `handleBoxSaved(_:)` 对所有服务端保存结果统一执行 upsert：

```text
handleBoxSaved -> viewModel.upsert(box) -> notifyParentCompleteDataIfFamily()
```

这不适合归档场景。归档后的对象虽然是服务端返回的有效对象，但不应该继续留在 active 家庭药箱列表里。

### 4.2 家庭药箱 ViewModel

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/FamilyMedicineCabinetViewModel.swift
```

关键位置：

1. `allBoxes`
2. `filteredBoxes`
3. `load()`
4. `upsert(_:)`
5. `remove(id:)`
6. `boxesForFamilyHomeCacheSync`

当前 `filteredBoxes` 没有过滤 `isArchived`。理论上家庭药箱 summary 接口只返回未归档药品，但归档 PATCH 成功后的本地 upsert 会把 `isArchived=true` 的药品塞进 `allBoxes`，因此 active 列表仍可能展示它。

### 4.3 药品网格

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/MedicineBoxGridView.swift
```

当前打开详情页时只传了：

```text
onSaved
onDeleted
```

没有传：

```text
onArchiveStateChanged
archiveMode
```

因此 `MedicineBoxDetailPage` 虽然已经支持归档状态回调，但家庭药箱网格没有接入这个回调。

### 4.4 药品详情页

```text
SparkClient/SparkClient/Projects/Features/Home/Presentation/MedicalLists/Medications/MedicineBox/MedicineBoxDetailPage.swift
```

归档成功后当前逻辑为：

```text
currentBox = updated
onSaved(updated)
onArchiveStateChanged?(updated.id, updated.isArchived)
let belongsInList = archiveMode == .archived ? updated.isArchived : !updated.isArchived
if belongsInList == false {
    dismiss()
}
```

这里的 `onArchiveStateChanged` 是正确方向，但上游未传入时不会生效。`onSaved(updated)` 在 active 列表场景下反而会造成归档药品被 upsert 回列表。

## 5. 根因分析

### 5.1 归档被当成普通保存处理

归档 PATCH 返回的是完整药品对象，且 `is_archived=true`。详情页把该对象交给 `onSaved(updated)` 后，家庭药箱页将其当作普通编辑保存：

```text
归档成功 -> onSaved(updated) -> upsert(updated) -> allBoxes 仍包含归档药品
```

这会导致 active 列表内存态和服务端 active 查询结果不一致。

### 5.2 归档状态回调没有从 Grid 传到 Detail

`MedicineBoxDetailPage` 已经预留：

```text
onArchiveStateChanged: ((Int, Bool) -> Void)?
archiveMode: MedicalArchiveListMode
```

但 `MedicineBoxGridView` 创建详情页时没有传这两个参数。结果是：

1. 详情页知道药品已归档。
2. 详情页可以 dismiss。
3. 上层列表不知道应该 remove 这个 id。

### 5.3 ViewModel 缺少 active 兜底过滤

家庭药箱业务上只展示 active 药品。即使服务端接口已正确过滤，客户端内存态也应该防御性过滤：

```text
active 列表不展示 isArchived=true 的药品
```

当前 `filteredBoxes` 只处理成员筛选、类型筛选、搜索，没有过滤归档状态。因此一旦本地被 upsert 了归档药品，它仍可能出现在列表中。

### 5.4 首页完整成员数据缓存被错误回写

`notifyParentCompleteDataIfFamily()` 会把 `viewModel.boxesForFamilyHomeCacheSync` 回写到 `completeData.familyMedicineBoxes`。

如果 `allBoxes` 中包含归档药品，首页缓存也会被写入归档药品：

```text
completeData.familyMedicineBoxes = viewModel.boxesForFamilyHomeCacheSync
```

这会导致返回首页或重新进入家庭药箱时，旧缓存继续污染页面。

### 5.5 personal 模式下不能依赖 family 回写日志判断成功

下拉刷新后如果没有看到：

```text
家庭药箱回写首页完整成员数据缓存
```

需要先确认当前页面模式。若当前页面是 `.personal`，这是符合代码预期的，因为：

```text
reloadAndNotifyParent -> notifyParentIfPersonal -> onMedicineBoxesChanged
reloadAndNotifyParent -> notifyParentCompleteDataIfFamily -> guard mode == .family 返回
```

也就是说，personal 模式应该补充或观察个人模式日志，而不是 family 缓存日志。

personal 模式真正需要验证的是：

1. `viewModel.load()` 返回后 `allBoxes.count` 是否变成 1。
2. `notifyParentIfPersonal()` 是否调用。
3. `onMedicineBoxesChanged` 收到的 boxes count 是否为 1。
4. 上层 `medicineBoxes` 状态是否被 count=1 覆盖。
5. `MedicineBoxGridView` 的 `boxes` 入参是否重新渲染为 count=1。

## 6. 修复目标

1. active 家庭药箱列表中，归档成功后立即移除该药品。
2. 归档成功后，首页 `familyMedicineBoxes` 缓存不得包含 `isArchived=true` 药品。
3. 手动下拉刷新后，以服务端返回列表为准替换 `allBoxes`。
4. 归档列表中取消归档后，该药品从归档列表移除。
5. 普通编辑保存仍然保持 upsert 行为。
6. 删除行为不受影响。

## 7. 推荐修复方案

### 7.1 区分“保存”和“归档状态变化”

`MedicineBoxDetailPage.updateArchiveState` 不应只通过 `onSaved(updated)` 驱动上层列表。

推荐顺序：

```text
currentBox = updated
onArchiveStateChanged?(updated.id, updated.isArchived)
如果当前详情仍属于当前列表，再 onSaved(updated)
否则 dismiss
```

或者在 active 列表场景下，归档成功不调用 `onSaved(updated)`，只调用 `onArchiveStateChanged`。

### 7.2 `MedicineBoxGridView` 透传归档回调

`MedicineBoxGridView` 增加参数：

```swift
let onArchiveStateChanged: ((Int, Bool) -> Void)?
let archiveMode: MedicalArchiveListMode
```

创建 `MedicineBoxDetailPage` 时传入：

```swift
onArchiveStateChanged: onArchiveStateChanged,
archiveMode: archiveMode
```

### 7.3 `FamilyMedicineCabinetPage` 实现归档状态处理

新增处理函数：

```swift
private func handleBoxArchiveStateChanged(id: Int, isArchived: Bool) {
    switch archiveMode / page mode {
    case active:
        if isArchived {
            viewModel.remove(id: id)
        }
    case archived:
        if !isArchived {
            viewModel.remove(id: id)
        }
    }
    notifyParentIfPersonal()
    notifyParentCompleteDataIfFamily()
}
```

家庭药箱页当前没有显式 `archiveMode`，可视为 `.active`。

### 7.4 `FamilyMedicineCabinetViewModel` 增加防御过滤

建议在 active 家庭药箱 ViewModel 中保证：

```swift
allBoxes = boxes.filter { !$0.isArchived }
```

至少在以下位置处理：

1. 初始化缓存写入时。
2. `load()` 接口返回赋值时。
3. `upsert(_:)` 时，如果 `box.isArchived == true`，active 模式应 remove 而不是 upsert。
4. `boxesForFamilyHomeCacheSync` 回写前过滤归档药品。

这样即使某个页面忘记处理归档回调，也不至于污染 active 列表。

### 7.5 刷新后强制替换而不是合并

`viewModel.load()` 已经是替换赋值：

```swift
allBoxes = boxes
```

需要确保后续没有父级旧缓存通过 `onMemberCompleteDataChanged` 或页面重建再次覆盖 `allBoxes`。

如果仍存在覆盖，应增加日志：

```text
家庭药箱刷新接口返回 count=1
FamilyMedicineCabinetViewModel.allBoxes 更新后 count=1
个人药箱回写上层缓存 entryMemberID=450 count=1
家庭药箱回写首页完整成员数据缓存 count=1
MedicineBoxGridView 渲染 boxes count=1
```

### 7.6 personal / family 模式分别补日志

建议把当前单一 family 回写日志拆成两条，避免排查时误判：

```text
个人药箱回写上层缓存 entryMemberID={id} count={count}
家庭药箱回写首页完整成员数据缓存 entryMemberID={id} count={count}
```

并在 guard 返回前补调试日志：

```text
跳过家庭药箱 completeData 回写 reason=not_family mode=personal
跳过家庭药箱 completeData 回写 reason=missing_complete_data mode=family
```

第一期可只加 personal 成功日志，不一定要长期保留 guard 调试日志。

## 8. 验收标准

1. 家庭药箱中有 2 个药品，归档其中 1 个后，返回列表立即只显示 1 个。
2. 归档成功后日志中的家庭药箱缓存回写 count 应为 1，而不是 2。
3. 下拉刷新家庭药箱后，列表数量与 `/medicine-cabinet/summary/` 返回数量一致。
4. 重新进入家庭药箱，不再出现已归档药品。
5. 进入归档药品列表，可以看到刚归档的药品。
6. 在归档药品详情中取消归档后，归档列表移除该药品。
7. 取消归档后回到家庭药箱刷新，该药品重新出现。
8. 普通编辑药品后，仍能在当前列表更新卡片内容。
9. 删除药品后，仍从当前列表移除。
10. personal 模式下拉刷新返回 1 条时，应出现个人药箱回写日志或上层状态更新日志。
11. family 模式下拉刷新返回 1 条时，应出现家庭药箱 completeData 回写日志。

## 9. 建议补充日志

建议临时增加以下诊断日志，验证状态流：

```text
药品归档状态更新成功 id={id} isArchived={isArchived}
家庭药箱处理归档状态变化 id={id} isArchived={isArchived} before={countBefore} after={countAfter}
家庭药箱 load 返回 count={serverCount}
家庭药箱 allBoxes 替换完成 count={allBoxesCount}
家庭药箱 filteredBoxes 渲染 count={filteredCount}
家庭药箱回写首页完整成员数据缓存 count={cacheCount}
```

## 10. 回归范围

1. 家庭药箱归档。
2. 个人药箱归档。
3. 归档药品列表。
4. 药品详情编辑。
5. 药品删除。
6. 家庭药箱按成员筛选。
7. 家庭药箱按药品类型筛选。
8. 家庭药箱搜索。
9. 首页完整成员数据缓存回写。
