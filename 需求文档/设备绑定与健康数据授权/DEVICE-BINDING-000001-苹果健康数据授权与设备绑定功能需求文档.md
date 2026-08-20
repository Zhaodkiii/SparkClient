# 苹果健康数据授权与设备绑定功能需求文档

**文档编号**: DEVICE-BINDING-000001  
**版本**: v1.0  
**创建日期**: 2026-08-20  
**状态**: 待评审  
**适用平台**: iOS (SparkClient)

---

## 目录

1. [功能概述](#1-功能概述)
2. [现有代码分析](#2-现有代码分析)
3. [核心数据模型设计](#3-核心数据模型设计)
4. [技术架构设计](#4-技术架构设计)
5. [界面设计规范](#5-界面设计规范)
6. [功能详细实现](#6-功能详细实现)
7. [健康数据访问控制机制](#7-健康数据访问控制机制)
8. [异常场景处理](#8-异常场景处理)
9. [本地数据安全与加密](#9-本地数据安全与加密)
10. [模块文件结构规划](#10-模块文件结构规划)
11. [测试要点](#11-测试要点)
12. [本地化字符串清单](#12-本地化字符串清单)

---

## 1. 功能概述

### 1.1 功能目标

本功能旨在实现以家庭成员为维度的苹果健康数据授权管理，建立成员与设备的绑定关系，确保每个成员的健康数据授权独立管理、数据访问权限严格隔离。所有健康数据仅在本地处理，设备绑定信息采用本地持久化存储，不与服务器同步。

### 1.2 核心特性

- ✅ 以家庭成员为维度的苹果健康数据授权获取
- ✅ 成员与当前设备的绑定关系管理（增删改查）
- ✅ 统一的健康数据访问权限检查机制
- ✅ "我的设备"页面：已绑定设备列表、切换绑定成员、删除绑定
- ✅ "添加设备"页面：数据来源选择（当前仅苹果健康可用）
- ✅ 成员详情页"数据来源"入口
- ✅ 权限收回异常处理与用户引导
- ✅ 本地数据加密存储
- ✅ 数据完全本地化，不上传服务器

### 1.3 业务规则

| 规则编号 | 规则描述 |
|---------|---------|
| BR-001 | 一个成员只能绑定一个健康数据来源账号 |
| BR-002 | 一个健康数据来源（如苹果健康）同一时间只能绑定一个成员 |
| BR-003 | 健康数据仅在本地设备处理，不同步到任何服务器 |
| BR-004 | 设备绑定信息完全本地存储，不上传服务器 |
| BR-005 | 所有健康数据访问必须通过三重校验：设备绑定检查 → 授权状态检查 → 成员权限检查 |
| BR-006 | 切换成员绑定时，需先解除原绑定关系 |
| BR-007 | 删除设备绑定需二次确认，防止误操作 |
| BR-008 | 用户收回系统健康权限后，需提示用户并引导重新授权 |

---

## 2. 现有代码分析

### 2.1 现有苹果健康授权核心代码位置

#### 2.1.1 SparkHealthTool（AI工具层健康数据封装）

**文件路径**: `SparkClient/Projects/Core/Health/SparkHealthTool.swift`

**核心功能**:
- 单例模式 `shared`，持有 `HKHealthStore` 实例
- 提供步数、距离、能量、营养、睡眠、运动等数据读取方法
- 内置授权请求方法 `requestAuthorization()`
- 支持写入营养数据到 HealthKit

**现有授权流程**:
```swift
// 第763-800行：授权请求
private func requestAuthorization() async throws {
    var readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
        HKObjectType.quantityType(forIdentifier: .distanceCycling)!
    ]
    // ... 补充可选类型
    try await requestAuthorization(readTypes: readTypes, writeTypes: [])
}
```

**现有机制优缺点分析**:

| 优点 | 缺点 |
|-----|------|
| 封装了HealthKit异步API为async/await | 单例模式，无法区分不同成员的授权状态 |
| 集中管理了所有需要的HealthKit类型 | 没有本地授权状态持久化 |
| 提供了丰富的健康数据读取方法 | 没有设备绑定概念 |
| 错误处理相对完善 | 每次调用都触发授权弹窗（即使已授权） |
| 支持写入营养数据 | 无法针对不同成员做权限隔离 |
| 有数据可视化模型支持 | 缺少授权状态实时监听机制 |

#### 2.1.2 NutritionHealthKitStore（营养模块HealthKit封装）

**文件路径**: `SparkClient/Projects/Features/Nutrition/Infrastructure/NutritionHealthKitStore.swift`

**核心功能**:
- 营养模块专用的HealthKit读写封装
- 区分本App写入与第三方App写入的样本
- 支持外部摄入样本读取与合并
- 支持用餐记录、能量消耗写入HealthKit

**与本功能的关系**:
- 现有营养模块已经在使用HealthKit，但同样没有成员维度隔离
- 后续需要改造为通过统一的访问控制层调用

### 2.2 现有成员模型

**文件路径**: `SparkClient/Projects/Core/Domain/Entities/Member.swift`

```swift
struct Member: Identifiable, Codable, Equatable, Sendable {
    let id: Int                  // 服务端成员ID
    var name: String             // 姓名
    var gender: String           // 性别
    var relationship: String     // 与本人关系（self/father等）
    var birthDate: Date?         // 出生日期
    var bloodType: String        // 血型
    var allergies: [String]      // 过敏史
    var chronicConditions: [String] // 慢病
    var notes: String            // 备注
    var avatarUrl: String        // 头像URL
    var isPrimary: Bool          // 是否主档案
    var updatedAt: Date          // 更新时间
    var binding: MemberBindingInfo? // 绑定信息
    
    var isSelfMember: Bool { ... } // 判断是否本人
}
```

**注意**: 现有Member模型是服务端同步的模型，设备绑定是本地概念，不应该修改现有Member结构，而是通过本地关联表实现。

### 2.3 现有成员详情页

**文件路径**: `SparkClient/Projects/Features/MemberContext/Presentation/MemberDetailView.swift`

现有模块总览包括：医疗、饮食两个模块。需要新增"数据来源"模块入口。

### 2.4 现有HealthKit权限配置

**文件路径**: `SparkClient/SparkClient.entitlements`
- 需确认已配置HealthKit能力

**Info.plist 权限描述**:
- `NSHealthShareUsageDescription`: 读取健康数据用途描述
- `NSHealthUpdateUsageDescription`: 写入健康数据用途描述

---

## 3. 核心数据模型设计

### 3.1 设备数据来源类型枚举

```swift
/// 健康数据来源类型
enum HealthDataSourceType: String, Codable, CaseIterable, Sendable {
    case appleHealth = "apple_health"           // 苹果健康
    case huaweiHealth = "huawei_health"         // 华为运动健康（预留，暂不接入）
    case vivoHealth = "vivo_health"             // vivo健康（预留，暂不接入）
    case coros = "coros"                        // COROS高驰（预留，暂不接入）
    
    /// 医疗器械类型
    case bloodPressureMonitor = "bp_monitor"    // 血压计（预留）
    case glucometer = "glucometer"              // 血糖仪（预留）
    
    /// 是否为当前阶段可用的数据源
    var isAvailable: Bool {
        switch self {
        case .appleHealth:
            return true
        default:
            return false
        }
    }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .appleHealth: return "苹果健康"
        case .huaweiHealth: return "华为运动健康"
        case .vivoHealth: return "vivo健康"
        case .coros: return "COROS高驰"
        case .bloodPressureMonitor: return "讯飞臂筒式血压计 X7"
        case .glucometer: return "血糖仪"
        }
    }
    
    /// 图标名称（SF Symbol或Assets）
    var iconName: String {
        switch self {
        case .appleHealth: return "apple.logo"
        case .huaweiHealth: return "heart.circle.fill"
        case .vivoHealth: return "heart.circle.fill"
        case .coros: return "figure.run.circle.fill"
        case .bloodPressureMonitor: return "gauge.medium"
        case .glucometer: return "drop.fill"
        }
    }
    
    /// 图标背景色
    var iconBackgroundColor: String {
        switch self {
        case .appleHealth: return "#000000"
        case .huaweiHealth: return "#FF6B00"
        case .vivoHealth: return "#34D399"
        case .coros: return "#1A1A1A"
        case .bloodPressureMonitor: return "#F3F4F6"
        case .glucometer: return "#F3F4F6"
        }
    }
    
    /// 分类
    var category: DataSourceCategory {
        switch self {
        case .appleHealth, .huaweiHealth, .vivoHealth, .coros:
            return .accountData
        case .bloodPressureMonitor, .glucometer:
            return .medicalDevice
        }
    }
}

/// 数据源分类
enum DataSourceCategory: String, Codable, Sendable {
    case accountData = "account_data"       // 账号数据
    case medicalDevice = "medical_device"   // 医疗器械
}
```

### 3.2 授权状态枚举

```swift
/// 健康数据授权状态
enum HealthAuthorizationStatus: String, Codable, Sendable {
    case notDetermined = "not_determined"   // 未请求授权
    case authorized = "authorized"          // 已授权
    case denied = "denied"                  // 已拒绝
    case partial = "partial"                // 部分授权（关键权限缺失）
    case revoked = "revoked"                // 曾授权后被收回
    
    /// 是否可以正常访问数据
    var canAccessData: Bool {
        self == .authorized
    }
    
    /// 显示状态文本
    var statusText: String {
        switch self {
        case .notDetermined: return "未授权"
        case .authorized: return "已同步"
        case .denied: return "已拒绝"
        case .partial: return "部分授权"
        case .revoked: return "数据异常"
        }
    }
    
    /// 状态颜色
    var statusColor: Color {
        switch self {
        case .authorized: return .green
        case .notDetermined, .partial: return .orange
        case .denied, .revoked: return .red
        }
    }
}
```

### 3.3 设备绑定模型

```swift
/// 设备绑定记录（本地持久化）
struct DeviceBinding: Identifiable, Codable, Equatable, Sendable {
    /// 绑定记录唯一ID（本地生成UUID）
    let id: String
    
    /// 数据来源类型
    let sourceType: HealthDataSourceType
    
    /// 绑定的成员ID（对应服务端Member.id）
    var memberId: Int
    
    /// 成员姓名（缓存，避免每次查成员列表）
    var memberName: String
    
    /// 成员关系（缓存）
    var memberRelationship: String
    
    /// 成员头像URL（缓存）
    var memberAvatarUrl: String
    
    /// 授权状态
    var authorizationStatus: HealthAuthorizationStatus
    
    /// 绑定时间
    let bindTime: Date
    
    /// 最后授权验证时间
    var lastAuthCheckTime: Date?
    
    /// 账号标识（如华为账号手机号，苹果健康无）
    var accountIdentifier: String?
    
    /// 账号显示文本（如"账号：153******20"）
    var accountDisplayText: String?
    
    /// 错误信息（授权异常时）
    var errorMessage: String?
    
    init(
        id: String = UUID().uuidString,
        sourceType: HealthDataSourceType,
        memberId: Int,
        memberName: String,
        memberRelationship: String,
        memberAvatarUrl: String = "",
        authorizationStatus: HealthAuthorizationStatus = .notDetermined,
        bindTime: Date = Date(),
        lastAuthCheckTime: Date? = nil,
        accountIdentifier: String? = nil,
        accountDisplayText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.memberId = memberId
        self.memberName = memberName
        self.memberRelationship = memberRelationship
        self.memberAvatarUrl = memberAvatarUrl
        self.authorizationStatus = authorizationStatus
        self.bindTime = bindTime
        self.lastAuthCheckTime = lastAuthCheckTime
        self.accountIdentifier = accountIdentifier
        self.accountDisplayText = accountDisplayText
        self.errorMessage = errorMessage
    }
}
```

### 3.4 数据访问权限检查结果

```swift
/// 健康数据访问检查结果
enum HealthDataAccessResult: Equatable, Sendable {
    case granted                          // 允许访问
    case noBinding(HealthDataSourceType)  // 未绑定设备
    case authorizationRevoked(DeviceBinding) // 授权被收回
    case authorizationDenied(DeviceBinding)  // 授权被拒绝
    case partialAuthorization(DeviceBinding, Set<String>) // 部分授权（缺失的权限Key）
    case memberNotBound(Int)              // 成员未绑定该数据源
    case dataSourceNotAvailable(HealthDataSourceType) // 数据源不可用
    case healthKitUnavailable             // 设备不支持HealthKit
    
    /// 是否允许访问
    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
    
    /// 错误描述（用于提示用户）
    var errorDescription: String? {
        switch self {
        case .granted:
            return nil
        case .noBinding:
            return "尚未绑定健康数据来源，请先在\"我的设备\"中添加"
        case .authorizationRevoked:
            return "无法获取数据，你的苹果健康可能暂无数据产生或系统权限未开启"
        case .authorizationDenied:
            return "健康数据权限被拒绝，请在系统设置中开启"
        case .partialAuthorization:
            return "部分健康数据权限未开启，可能导致数据不完整"
        case .memberNotBound:
            return "当前成员未绑定健康数据来源"
        case .dataSourceNotAvailable(let type):
            return "\(type.displayName)暂未接入，敬请期待"
        case .healthKitUnavailable:
            return "当前设备不支持健康数据功能"
        }
    }
    
    /// 是否需要显示权限引导弹窗
    var shouldShowPermissionGuide: Bool {
        switch self {
        case .authorizationRevoked, .authorizationDenied, .partialAuthorization:
            return true
        default:
            return false
        }
    }
}
```

---

## 4. 技术架构设计

### 4.1 整体架构分层

```
┌─────────────────────────────────────────────────────────────┐
│                      Presentation Layer                     │
│  ┌─────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │ 我的设备页面 │  │ 添加设备页面     │  │ 成员选择弹窗    │  │
│  └─────────────┘  └─────────────────┘  └────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              权限异常引导弹窗                         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                       │
│  ┌──────────────────────┐  ┌─────────────────────────────┐  │
│  │  DeviceBindingUseCase│  │ HealthAuthorizationUseCase  │  │
│  │  - 绑定/解绑/切换    │  │  - 请求授权                  │  │
│  │  - 列表查询          │  │  - 检查授权状态              │  │
│  │  - 持久化            │  │  - 监听授权变化              │  │
│  └──────────────────────┘  └─────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           HealthDataAccessGate (访问控制网关)         │   │
│  │  - 三重校验：绑定→授权→成员权限                       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                     │
│  ┌──────────────────────┐  ┌─────────────────────────────┐  │
│  │ DeviceBindingStore   │  │ HealthKitAuthorizationStore │  │
│  │  - 本地CRUD          │  │  - HKHealthStore封装         │  │
│  │  - 加密存储          │  │  - 授权状态查询              │  │
│  └──────────────────────┘  └─────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          SecureLocalStorage (加密本地存储)            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                           │
│  ┌─────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │ 实体模型     │  │ 枚举定义         │  │ 错误类型        │  │
│  └─────────────┘  └─────────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 核心组件职责说明

#### 4.2.1 SecureLocalStorage - 安全本地存储

**职责**:
- 使用iOS Keychain或加密的UserDefaults存储敏感数据
- 设备绑定信息需加密存储，防止iCloud备份泄露
- 提供线程安全的读写接口

**技术方案**:
- 优先使用Keychain存储绑定信息
- Keychain使用`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`属性，禁止iCloud同步
- 如果数据量较大，可使用加密的Core Data或SQLite，密钥存Keychain

#### 4.2.2 DeviceBindingStore - 设备绑定存储

**职责**:
- 设备绑定记录的CRUD操作
- 按成员ID、数据源类型查询绑定
- 保证数据一致性（一个数据源只能绑定一个成员）

**关键接口**:
```swift
protocol DeviceBindingStoreProtocol: Sendable {
    /// 获取所有绑定记录
    func fetchAllBindings() async throws -> [DeviceBinding]
    
    /// 获取指定数据源的绑定记录
    func fetchBinding(for sourceType: HealthDataSourceType) async throws -> DeviceBinding?
    
    /// 获取指定成员的绑定记录（一个成员可绑定多个不同类型数据源？不，当前规则BR-001是一个成员一个健康账号，但可绑定不同类型设备）
    /// 修正：一个成员可以绑定多个不同类型的数据源（苹果健康、血压计等），但同一类型只能绑定一个
    func fetchBindings(for memberId: Int) async throws -> [DeviceBinding]
    
    /// 保存/更新绑定记录
    func saveBinding(_ binding: DeviceBinding) async throws
    
    /// 删除绑定记录
    func deleteBinding(id: String) async throws
    
    /// 删除指定数据源的绑定
    func deleteBinding(for sourceType: HealthDataSourceType) async throws
    
    /// 检查数据源是否已被绑定
    func isSourceBound(_ sourceType: HealthDataSourceType) async throws -> Bool
    
    /// 检查成员是否已绑定指定类型数据源
    func isMemberBound(_ memberId: Int, sourceType: HealthDataSourceType) async throws -> Bool
}
```

#### 4.2.3 HealthKitAuthorizationStore - HealthKit授权封装

**职责**:
- 封装HKHealthStore，避免上层直接依赖HealthKit
- 提供授权请求、状态检查、变化监听
- 按成员维度管理授权上下文（因为HealthKit是系统级授权，但我们需要记录哪个成员绑定了它）

**关键接口**:
```swift
protocol HealthKitAuthorizationStoreProtocol: Sendable {
    /// 设备是否支持HealthKit
    var isHealthDataAvailable: Bool { get }
    
    /// 请求苹果健康授权（针对指定绑定）
    func requestAuthorization(for binding: DeviceBinding) async throws -> HealthAuthorizationStatus
    
    /// 检查当前授权状态（实时查询系统）
    func checkAuthorizationStatus(for binding: DeviceBinding) async -> HealthAuthorizationStatus
    
    /// 获取HKHealthStore实例（仅供数据读取层使用）
    var healthStore: HKHealthStore { get }
    
    /// 开始监听授权状态变化
    func startObservingAuthorizationChanges() -> AsyncStream<HealthAuthorizationStatus>
}
```

#### 4.2.4 DeviceBindingUseCase - 设备绑定用例

**职责**:
- 协调绑定流程：创建绑定 → 请求授权 → 更新状态 → 持久化
- 处理绑定冲突：数据源已绑定其他成员时的切换逻辑
- 提供给UI层的业务操作接口

**关键接口**:
```swift
@MainActor
final class DeviceBindingUseCase: ObservableObject {
    // MARK: - Published State
    @Published private(set) var bindings: [DeviceBinding] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Initialization
    init(
        bindingStore: DeviceBindingStoreProtocol,
        authStore: HealthKitAuthorizationStoreProtocol,
        memberContextStore: MemberContextStore
    )
    
    // MARK: - Public Methods
    
    /// 加载所有绑定
    func loadBindings() async
    
    /// 绑定数据源到指定成员
    /// - Parameters:
    ///   - sourceType: 数据源类型
    ///   - member: 目标成员
    /// - Throws: 绑定冲突、授权失败等错误
    func bindSource(
        _ sourceType: HealthDataSourceType,
        to member: Member
    ) async throws -> DeviceBinding
    
    /// 切换已绑定数据源的成员
    /// - Parameters:
    ///   - sourceType: 数据源类型
    ///   - newMember: 新成员
    /// 注意：会先解除与原成员的绑定
    func switchBinding(
        for sourceType: HealthDataSourceType,
        to newMember: Member
    ) async throws
    
    /// 解绑指定数据源
    /// - Parameter sourceType: 数据源类型
    func unbindSource(_ sourceType: HealthDataSourceType) async throws
    
    /// 解绑指定绑定记录
    func unbindBinding(_ binding: DeviceBinding) async throws
    
    /// 获取数据源当前绑定的成员
    func getBoundMember(for sourceType: HealthDataSourceType) -> Member?
    
    /// 检查指定成员是否可以绑定该数据源
    /// 返回：(canBind: Bool, existingBinding: DeviceBinding?)
    func canBind(
        sourceType: HealthDataSourceType,
        member: Member
    ) async -> (Bool, DeviceBinding?)
    
    /// 重新验证所有绑定的授权状态
    func refreshAllAuthorizationStatus() async
    
    /// 处理用户点击"数据异常"的跳转引导
    func handleAuthError(for binding: DeviceBinding) -> PermissionGuideAction
}
```

#### 4.2.5 HealthDataAccessGate - 健康数据访问网关

**职责**（核心！）:
- 所有健康数据访问的统一入口
- 执行三重权限校验
- 提供给AI工具、营养模块、首页健康卡片等所有使用健康数据的地方
- 拒绝不满足条件的数据访问请求

**关键接口**:
```swift
/// 健康数据访问网关 - 所有健康数据访问必须经过此网关
final class HealthDataAccessGate: Sendable {
    static let shared = HealthDataAccessGate()
    
    private init() {}
    
    // MARK: - 配置（依赖注入）
    func configure(
        bindingStore: DeviceBindingStoreProtocol,
        authStore: HealthKitAuthorizationStoreProtocol,
        memberContextStore: MemberContextStore
    )
    
    // MARK: - 访问检查
    
    /// 检查当前选中成员是否可以访问指定类型的健康数据
    /// - Parameters:
    ///   - sourceType: 数据源类型（默认苹果健康）
    ///   - memberId: 成员ID，nil表示使用当前上下文选中的成员
    /// - Returns: 访问检查结果
    func checkAccess(
        for sourceType: HealthDataSourceType = .appleHealth,
        memberId: Int? = nil
    ) async -> HealthDataAccessResult
    
    /// 检查访问权限，若允许则返回可用的HKHealthStore和绑定信息
    /// 用于需要直接访问HealthKit的场景
    /// - Throws: 如果访问不通过，抛出错误
    /// - Returns: (healthStore, binding) 元组
    func validateAndGetHealthStore(
        for sourceType: HealthDataSourceType = .appleHealth,
        memberId: Int? = nil
    ) async throws -> (HKHealthStore, DeviceBinding)
    
    /// 安全执行健康数据查询（包裹检查逻辑）
    /// - Parameters:
    ///   - sourceType: 数据源类型
    ///   - memberId: 成员ID
    ///   - operation: 数据查询操作
    /// - Returns: 查询结果或访问错误
    func performSecureQuery<T: Sendable>(
        for sourceType: HealthDataSourceType = .appleHealth,
        memberId: Int? = nil,
        operation: @Sendable (HKHealthStore, DeviceBinding) async throws -> T
    ) async -> Result<T, HealthDataAccessResult>
}
```

### 4.3 授权状态监听机制

```swift
// 在App启动时开始监听授权变化
extension AppBootstrapper {
    func setupHealthAuthorizationObserver() {
        Task {
            let authStore = HealthKitAuthorizationStore.shared
            for await status in authStore.startObservingAuthorizationChanges() {
                // 授权状态变化时，更新对应绑定记录
                await DeviceBindingUseCase.shared.refreshAllAuthorizationStatus()
                
                // 如果当前有页面需要显示异常弹窗，发送通知
                if status != .authorized {
                    NotificationCenter.default.post(
                        name: .healthAuthorizationStatusChanged,
                        object: nil,
                        userInfo: ["status": status]
                    )
                }
            }
        }
    }
}

extension Notification.Name {
    static let healthAuthorizationStatusChanged = Notification.Name("HealthAuthorizationStatusChanged")
}
```

---

## 5. 界面设计规范

### 5.1 我的设备页面

#### 5.1.1 页面结构（参考设计图1）

```
┌─────────────────────────────────────────────────────────────┐
│  ←  我的设备                                          ✕     │ ← 导航栏（关闭按钮在左还是右？参考设计图左上角是返回）
├─────────────────────────────────────────────────────────────┤
│  账号数据                        一个成员只能绑定一个健康账号  │ ← 分组标题 + 提示
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │  [icon] 华为运动健康数据                          🗑  │   │
│  │         账号：153******20                            │   │
│  │         [🔴 数据异常 >]                              │   │ ← 异常时显示
│  │  ─────────────────────────────────────────────────  │   │
│  │  [avatar] 爸爸 57岁                    切换绑定      │   │
│  └─────────────────────────────────────────────────────┘   │ ← 设备卡片
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  [icon] 苹果健康                                  🗑  │   │
│  │         [🔴 数据异常 >]                              │   │ ← 有异常时显示在标题下方
│  │  ─────────────────────────────────────────────────  │   │
│  │  [avatar] 本人 --岁                    切换绑定      │   │
│  └─────────────────────────────────────────────────────┘   │ ← 苹果健康卡片
│                                                             │
│                                                             │
│                                                             │
│                                                             │
│                                                             │
│                              [  + 添加设备  ]               │ ← 底部按钮
└─────────────────────────────────────────────────────────────┘
```

#### 5.1.2 视觉规范

| 元素 | 规格 |
|-----|------|
| 页面背景 | `systemGroupedBackground` (F2F3F5/深色模式适配) |
| 卡片背景 | `secondarySystemGroupedBackground`，圆角16pt |
| 卡片间距 | 12pt |
| 卡片内边距 | 16pt |
| 设备图标 | 44x44pt，圆角12pt，居中显示logo |
| 删除图标 | 垃圾桶图标，灰色，点击区域44x44pt |
| 分隔线 | 0.5pt，灰色，左右保留16pt边距 |
| 异常标签 | 红色背景胶囊，白色/红色文字（参考"数据异常"样式），点击可跳转 |
| 成员头像 | 40x40pt，圆形 |
| 切换绑定按钮 | 文字按钮，accentColor |
| 底部添加按钮 | 蓝色背景(#2563EB)，白色文字，圆角12pt，高度50pt，左右16pt边距 |

#### 5.1.3 我的设备页面状态

| 状态 | 展示内容 |
|-----|---------|
| 空状态 | 显示空态图 + "暂无绑定设备，点击下方按钮添加"提示 |
| 正常状态 | 设备列表 + 添加按钮 |
| 加载中 | 列表显示骨架屏 |
| 授权异常 | 对应卡片显示"数据异常"标签，红色标记 |

### 5.2 切换绑定成员弹窗（参考设计图2）

```
┌─────────────────────────────────────────────────────────────┐
│  (背景半透明遮罩)                                            │
│                                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              切换绑定成员                        ✕  │   │ ← 弹窗标题
│  ├─────────────────────────────────────────────────────┤   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │ [avatar] 本人 [已绑定]                  ✓   │    │   │ ← 当前绑定成员（蓝色文字+标签+对勾）
│  │  └─────────────────────────────────────────────┘    │   │
│  │  ─────────────────────────────────────────────────  │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │ [avatar] 爸爸 57岁                          │    │   │ ← 其他成员
│  │  └─────────────────────────────────────────────┘    │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**交互说明**:
- 弹窗为底部Sheet样式，圆角顶部
- 点击成员行立即切换绑定，并关闭弹窗
- 已绑定的当前成员显示蓝色文字+「已绑定」标签+右侧蓝色对勾
- 右上角关闭按钮
- 点击遮罩区域关闭弹窗（可选）

### 5.3 添加设备页面（参考设计图3）

```
┌─────────────────────────────────────────────────────────────┐
│  ←  选择并添加设备                                          │
├─────────────────────────────────────────────────────────────┤
│  选择并添加设备                                              │ ← 大标题
│  同步设备数据，为你提供更精准的健康解读服务                     │ ← 副标题
├─────────────────────────────────────────────────────────────┤
│  账号数据                                                    │ ← 分组标题
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [icon] 华为运动健康                         [已同步] │   │
│  │        支持用户将HUAWEI Health账号的健康数据          │   │
│  │        同步至讯飞晓医                                │   │
│  └─────────────────────────────────────────────────────┘   │ ← 已绑定的显示"已同步"（置灰）
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [icon] 苹果健康                            [已同步]  │   │
│  │        支持用户将苹果账号下的健康数据同步至讯飞晓医     │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [icon] vivo健康                           [去同步]  │   │
│  │        支持用户将vivo账号下的健康数据同步至讯飞晓医     │   │
│  └─────────────────────────────────────────────────────┘   │ ← 未接入的显示"去同步"但整体置灰，点击提示"暂未开通"
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [icon] COROS高驰                          [去同步]  │   │
│  │        支持用户将COROS账号下的健康数据同步至讯飞晓医   │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  医疗器械                                                    │
│  [全部] [血压计] [血糖仪]                                    │ ← 分类Tab
│  ┌─────────────────────────────────────────────────────┐   │
│  │ [img] 讯飞臂筒式血压计 X7                  [去绑定] │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**交互说明**:
- 已绑定（已同步）的账号数据源：整体正常显示，按钮为灰色"已同步"，点击卡片无反应
- 未绑定但已接入的（当前只有苹果健康未绑定时）：显示"去同步"蓝色按钮，点击进入绑定流程（选择成员→请求授权）
- 未接入的数据源：整体透明度50%置灰，按钮显示"去同步"，点击弹出toast"该数据源暂未接入，敬请期待"
- 医疗器械部分：血压计、血糖仪所有选项整体置灰50%，点击同样提示"医疗器械功能暂未接入，敬请期待"
- 苹果健康图标使用苹果logo（黑色方块背景白色苹果）

### 5.4 解绑确认弹窗（参考设计图4）

```
┌─────────────────────────────────────────────────────────────┐
│  (背景半透明遮罩)                                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 解绑设备                             │   │
│  │         是否确认解绑当前设备？                        │   │
│  ├──────────────────────┬──────────────────────────────┤   │
│  │      再想想           │           解绑               │   │
│  │                      │        (红色文字)             │   │
│  └──────────────────────┴──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**交互说明**:
- 居中弹窗样式
- "再想想"为取消按钮，灰色文字
- "解绑"为红色文字，点击执行解绑并关闭弹窗
- 点击遮罩不关闭（防止误触）

### 5.5 权限异常提示弹窗（参考设计图5）

```
┌─────────────────────────────────────────────────────────────┐
│  (背景半透明遮罩)                                            │
│                                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              温馨提示                           ✕  │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │                                                      │   │
│  │  无法获取数据，你的苹果健康可能暂无数据产生或           │   │
│  │  系统权限未开启。                                     │   │
│  │                                                      │   │
│  │  请前往【设置-隐私与安全-健康-讯飞晓医】进行操作。      │   │
│  │                                                      │   │
│  │  ┌──────────────────┐  ┌──────────────────┐         │   │
│  │  │ [设置路径示意图1]│  │ [设置路径示意图2]│         │   │ ← 引导配图
│  │  │  健康设置入口    │  │  权限开关        │         │   │
│  │  └──────────────────┘  └──────────────────┘         │   │
│  │                                                      │   │
│  │              [ 知道了 ]                              │   │ ← 蓝色按钮
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**交互说明**:
- 底部Sheet或居中弹窗
- 显示详细错误说明
- 包含两张操作引导配图（设计图提供）
- "知道了"按钮关闭弹窗
- 右上角关闭按钮
- 可选：增加"去设置"按钮，直接跳转到系统设置

### 5.6 成员详情页 - 数据来源入口

在成员详情页的`moduleOverviewSection`中，新增"数据来源"模块行：

```swift
// 在医疗、饮食模块之后新增
Divider()
moduleRow(
    systemImage: "heart.circle.fill",
    title: "数据来源",
    status: dataSourceStatusText,
    summary: dataSourceSummary,
    actionTitle: dataSourceActionTitle,
    tint: Color(uiColor: .systemRed)
) {
    openDataSourceManagement()
}
```

**状态逻辑**:
- 已绑定苹果健康：显示"已绑定"，summary显示"苹果健康"
- 未绑定：显示"未绑定"，actionTitle为"去绑定"

点击跳转到"我的设备"页面（或本成员专属的数据源管理页，简化版可直接跳我的设备）。

---

## 6. 功能详细实现

### 6.1 模块入口与路由

#### 6.1.1 "我的设备"入口位置

需要在"我的"（个人中心）页面添加"我的设备"入口。

> **注意**: 需要根据现有项目结构找到个人中心页面位置，通常在Profile/Settings模块。如果没有明确入口，可以先：
> 1. 在成员详情页添加"数据来源"入口（跳转到我的设备页）
> 2. 后续在个人中心补加入口

#### 6.1.2 路由定义

```swift
// 在Feature路由枚举中添加
enum AppRoute: Hashable {
    // ... 现有路由
    case myDevices           // 我的设备列表页
    case addDevice           // 添加设备页
    case memberDataSource(memberId: Int) // 成员数据源管理
}
```

### 6.2 苹果健康绑定流程

**完整流程图**:

```
用户点击"添加设备" → 选择"苹果健康"（去同步）
        ↓
弹出成员选择列表（选择要绑定的成员）
        ↓
检查该成员是否已绑定其他健康账号？
        ├─ 是 → 提示"该成员已绑定其他健康账号，是否切换？"
        │       ├─ 确认 → 继续
        │       └─ 取消 → 返回
        └─ 否 → 继续
        ↓
检查苹果健康是否已被其他成员绑定？
        ├─ 是 → 弹窗提示"苹果健康当前已绑定给「XXX」，是否切换绑定到「YYY」？"
        │       ├─ 确认 → 解除原绑定，继续
        │       └─ 取消 → 返回
        └─ 否 → 继续
        ↓
调用 HKHealthStore.requestAuthorization 请求系统授权
        ↓
用户授权结果？
        ├─ 用户允许 → 检查实际授权状态（是否所有关键权限都给了）
        │       ├─ 完全授权 → 状态: .authorized
        │       └─ 部分授权 → 状态: .partial，记录缺失权限
        ├─ 用户拒绝 → 状态: .denied
        └─ 系统错误 → 抛出错误，提示用户
        ↓
创建DeviceBinding记录，持久化到本地
        ↓
刷新我的设备列表，显示新绑定
        ↓
发送绑定成功通知，可触发首次健康数据同步（可选）
```

**代码实现示例（UseCase层）**:

```swift
func bindAppleHealth(to member: Member) async throws -> DeviceBinding {
    isLoading = true
    defer { isLoading = false }
    
    // 1. 检查数据源可用性
    guard HealthDataSourceType.appleHealth.isAvailable else {
        throw DeviceBindingError.sourceNotAvailable
    }
    
    // 2. 检查HealthKit是否可用
    guard authStore.isHealthDataAvailable else {
        throw DeviceBindingError.healthKitUnavailable
    }
    
    // 3. 检查成员是否已绑定苹果健康
    let existingBindings = try await bindingStore.fetchBindings(for: member.id)
    if let existing = existingBindings.first(where: { $0.sourceType == .appleHealth }) {
        // 已绑定，直接返回
        return existing
    }
    
    // 4. 检查苹果健康是否已绑定其他成员
    if let existingBinding = try await bindingStore.fetchBinding(for: .appleHealth) {
        // 已绑定其他成员，需要先由UI层确认再调用switchBinding
        throw DeviceBindingError.alreadyBoundToOtherMember(existingBinding)
    }
    
    // 5. 创建待保存的绑定记录
    var binding = DeviceBinding(
        sourceType: .appleHealth,
        memberId: member.id,
        memberName: member.name,
        memberRelationship: member.relationship,
        memberAvatarUrl: member.avatarUrl,
        authorizationStatus: .notDetermined
    )
    
    // 6. 请求授权
    let status = try await authStore.requestAuthorization(for: binding)
    binding.authorizationStatus = status
    binding.lastAuthCheckTime = Date()
    
    // 7. 持久化
    try await bindingStore.saveBinding(binding)
    
    // 8. 刷新列表
    await loadBindings()
    
    return binding
}
```

### 6.3 切换绑定成员流程

```
用户点击设备卡片上的"切换绑定"
        ↓
弹出"切换绑定成员"底部弹窗，显示所有家庭成员列表
        ↓
用户选择新成员
        ↓
检查新成员是否已绑定同类型数据源？
        ├─ 是 → 提示"该成员已绑定同类健康账号，无法切换"
        └─ 否 → 继续
        ↓
更新DeviceBinding的memberId、memberName等信息
        ↓
（系统级HealthKit授权不需要重新请求，因为是设备级授权）
        ↓
重新验证授权状态
        ↓
持久化更新，刷新列表
        ↓
关闭弹窗，显示成功提示（轻量反馈）
```

### 6.4 解绑流程

```
用户点击卡片右上角垃圾桶图标
        ↓
弹出"解绑设备"确认弹窗
        ├─ 点击"再想想" → 关闭弹窗，不操作
        └─ 点击"解绑"（红色）→ 执行解绑
                ↓
删除DeviceBinding记录
                ↓
（可选：停止相关健康数据同步）
                ↓
刷新列表，卡片消失
                ↓
Haptic轻反馈 + 成功toast（可选）
```

**注意**: 解绑只删除本地绑定记录，**不会**撤销系统级的HealthKit授权。用户如果想彻底撤销授权，需要去系统设置操作。

---

## 7. 健康数据访问控制机制

### 7.1 三重校验机制详解

所有需要访问健康数据的地方**必须**调用`HealthDataAccessGate`，禁止直接使用`HKHealthStore`。

#### 第一重：设备绑定检查

验证当前成员是否已绑定对应的健康数据来源。

```swift
// 伪代码
async func checkBinding(memberId: Int, sourceType: HealthDataSourceType) -> DeviceBinding? {
    // 1. 查询该数据源是否有绑定记录
    guard let binding = try await bindingStore.fetchBinding(for: sourceType) else {
        return nil  // 没有绑定 → .noBinding
    }
    // 2. 检查绑定的成员是否是当前请求的成员
    guard binding.memberId == memberId else {
        return nil  // 成员不匹配 → .memberNotBound
    }
    return binding
}
```

#### 第二重：授权状态验证

实时查询HealthKit的授权状态，不是只用本地缓存的状态。

```swift
// 伪代码
func checkAuthorization(binding: DeviceBinding) async -> HealthAuthorizationStatus {
    // 1. 读取每个需要的HKObjectType的授权状态
    var deniedTypes: Set<String> = []
    for type in requiredHealthKitTypes() {
        let status = healthStore.authorizationStatus(for: type)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            deniedTypes.insert(type.identifier)
        case .sharingAuthorized:
            continue
        @unknown default:
            deniedTypes.insert(type.identifier)
        }
    }
    
    // 2. 判断整体状态
    if deniedTypes.isEmpty {
        return .authorized
    } else if deniedTypes.count == requiredHealthKitTypes().count {
        return .denied
    } else {
        return .partial
    }
}
```

> **重要提示**: 由于iOS的隐私限制，`authorizationStatus(for:)`在用户未明确授权前可能返回`.sharingDenied`。对于写入权限，我们无法准确读取状态。因此读权限（share）是我们检查的重点。

#### 第三重：成员权限检查

确保请求的数据属于绑定的成员，防止跨成员访问数据。

在当前阶段，因为HealthKit是设备级数据源，本身不区分成员数据（所有数据来自同一个iPhone/Apple Watch），所以这一重主要是：
- 确认当前上下文确实在查看该绑定成员的数据
- 防止在查看其他成员时错误地返回了本人的健康数据

**实现方式**:
- 所有健康数据查询必须传入`memberId`
- 网关检查`memberId`与绑定的`memberId`一致
- 如果不一致，即使授权有效也拒绝访问

### 7.2 改造现有代码接入访问网关

#### 7.2.1 改造SparkHealthTool

**文件**: `SparkClient/Projects/Core/Health/SparkHealthTool.swift`

改造点：
1. 移除单例中直接使用的`HKHealthStore`，改为通过网关获取
2. 所有公共方法增加`memberId`参数
3. 每次数据查询前先调用`validateAndGetHealthStore`
4. 授权请求不再由SparkHealthTool直接发起，而是走绑定流程

改造示例:
```swift
// 改造前
final class SparkHealthTool: @unchecked Sendable {
    static let shared = SparkHealthTool()
    private let healthStore = HKHealthStore()
    
    func fetchStepDetails(from startDate: Date, to endDate: Date) async -> String {
        // ... 直接使用healthStore
    }
}

// 改造后
final class SparkHealthTool: @unchecked Sendable {
    static let shared = SparkHealthTool()
    
    func fetchStepDetails(
        for memberId: Int,
        from startDate: Date,
        to endDate: Date
    ) async -> String {
        let result = await HealthDataAccessGate.shared.performSecureQuery(
            for: .appleHealth,
            memberId: memberId
        ) { healthStore, binding in
            // 实际查询逻辑，使用传入的healthStore
            return try await self.performStepQuery(
                healthStore: healthStore,
                startDate: startDate,
                endDate: endDate
            )
        }
        
        switch result {
        case .success(let data):
            return data
        case .failure(let accessError):
            return accessError.errorDescription ?? "健康数据访问失败"
        }
    }
}
```

#### 7.2.2 改造NutritionHealthKitStore

类似SparkHealthTool，所有读写操作通过网关验证。

#### 7.2.3 首页健康卡片

首页的运动、步数、睡眠等卡片，读取当前选中成员的健康数据前，先通过网关检查。如果未绑定或授权异常，显示对应状态：
- 未绑定：显示"去绑定"引导卡片
- 授权被收回：显示"数据异常，点击修复"提示
- 正常：显示健康数据

### 7.3 默认成员（本人）的自动绑定建议

考虑到用户体验，首次启动时如果检测到是本人成员，可以提示是否开启苹果健康同步：
- 不强制自动绑定（需要用户主动授权）
- 但可以在首页本人视角的健康卡片上显示醒目的"开启健康数据同步"引导
- 用户点击后走完整绑定流程

---

## 8. 异常场景处理

### 8.1 异常场景清单与处理策略

| 场景ID | 异常场景 | 触发时机 | 用户提示 | 降级策略 |
|--------|---------|---------|---------|---------|
| E-001 | 用户绑定后收回系统健康权限 | App启动/前台恢复/查询数据时检测到授权状态变化 | 弹出"温馨提示"弹窗（图5），说明权限被收回，引导到系统设置开启 | 1. 所有健康数据卡片显示"数据异常"状态<br>2. AI工具查询健康数据返回友好提示，不崩溃<br>3. 我的设备页对应卡片显示红色"数据异常"标签 |
| E-002 | 用户在系统弹窗中点击"不允许" | 首次请求授权时 | 不弹强制弹窗，在我的设备页显示授权状态为"已拒绝"，点击"数据异常"可查看引导 | 1. 绑定记录状态保存为.denied<br>2. 健康数据区域显示"未授权"提示，有"去开启"按钮<br>3. 不强制弹窗打扰用户 |
| E-003 | 用户只给了部分权限（如只给了步数，不给睡眠） | 授权完成后检查 | 不阻断使用，记录缺失权限，在相关数据缺失时提示 | 1. 有授权的数据正常读取显示<br>2. 未授权的模块显示"权限未开启"提示<br>3. 可在数据异常引导页提示开启完整权限 |
| E-004 | 设备不支持HealthKit（如iPad部分机型、模拟器） | 进入添加设备页/绑定时 | 苹果健康选项显示"设备不支持"置灰状态 | 1. 苹果健康cell整体置灰<br>2. 点击提示"当前设备不支持苹果健康" |
| E-005 | 网络异常（注：本功能纯本地，网络不影响，但可能影响成员列表加载） | 绑定流程中成员列表加载失败 | 显示"成员加载失败，请检查网络"，提供重试 | 绑定功能本身不需要网络，但成员列表来自服务端，需要网络加载成员 |
| E-006 | 绑定过程中App被杀死 | 下次启动时 | 无感知，通过本地持久化恢复状态 | 1. 启动时检查未完成的绑定记录，如果授权状态是notDetermined可以提示继续绑定<br>2. 或者直接清理未完成的绑定（更简单） |
| E-007 | 尝试把已绑定其他成员的数据源绑定给新成员 | 绑定/切换时 | 弹窗明确告知"苹果健康当前绑定给「爸爸」，切换后将解绑原成员"，需要用户二次确认 | 用户确认后才执行切换，不自动切换 |
| E-008 | 尝试给已绑定其他数据源的成员再绑苹果健康 | 绑定选择成员时 | 提示"该成员已绑定华为运动健康，一个成员只能绑定一个健康账号" | 不允许绑定，需要先解绑原有账号 |
| E-009 | HealthKit查询返回空数据 | 数据查询时 | 不弹错误弹窗，在数据展示区域显示"暂无数据" | 区分"权限不足"和"真的没有数据"两种空状态 |
| E-010 | 本地存储读写失败（Keychain访问错误） | 绑定/解绑/加载时 | 轻量toast提示"设备数据读取失败，请重启App重试" | 功能暂时不可用，不崩溃 |

### 8.2 权限收回（E-001）详细处理流程

这是最常见的异常场景，处理必须完善：

```
App从后台回到前台 / 启动 / 每次数据查询前
        ↓
调用HealthKitAuthorizationStore.checkAuthorizationStatus
        ↓
状态变为 .denied / .revoked / .partial？
        ├─ 否 → 正常
        └─ 是 → 更新本地DeviceBinding.authorizationStatus
                ↓
                发送通知 .healthAuthorizationStatusChanged
                ↓
                当前页面是否是健康数据相关页面？
                ├─ 是 → 弹出温馨提示弹窗（图5样式）
                │       1. 说明无法获取数据
                │       2. 给出设置路径
                │       3. 展示引导配图
                │       4. "知道了"关闭按钮
                │       5. （可选）"去设置"按钮，直接打开App设置页
                └─ 否 → 不弹窗，只在对应入口（我的设备卡片、首页卡片）显示异常标记
                        当用户主动进入相关页面时再弹窗提示
```

**跳转系统设置代码**:
```swift
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString),
          UIApplication.shared.canOpenURL(url) else {
        return
    }
    UIApplication.shared.open(url)
}
```

### 8.3 异常状态UI展示标准

| 状态 | 卡片标记 | 数据区域展示 |
|-----|---------|------------|
| `.authorized` 正常 | 无特殊标记，显示绑定成员 | 正常展示数据 |
| `.notDetermined` 未请求授权 | 黄色"待授权"标签 | 显示"点击开启健康数据同步"引导 |
| `.denied` 已拒绝 | 红色"数据异常"标签 | 显示"权限被拒绝，点击修复"占位 |
| `.partial` 部分授权 | 黄色"部分权限"标签 | 有权限的数据正常显示，无权限的显示提示 |
| `.revoked` 已收回 | 红色"数据异常"标签 | 同denied |

---

## 9. 本地数据安全与加密

### 9.1 存储安全要求

根据需求"健康数据仅在本地处理"、"设备绑定信息采用本地持久化存储"，必须满足：

1. **禁止iCloud同步**: 所有本地数据使用`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不备份到iCloud
2. **加密存储**: 设备绑定信息必须加密后存储，不能明文存UserDefaults
3. **不上传服务器**: 严格禁止将DeviceBinding、HealthKit数据上传到任何服务端接口
4. **不打印日志**: 健康数据、绑定信息禁止在Release包中打印到控制台

### 9.2 存储方案实现

使用Keychain存储绑定数据，因为Keychain本身有加密保护，且由系统管理安全。

```swift
/// Keychain存储封装
final class KeychainHelper: @unchecked Sendable {
    static let shared = KeychainHelper()
    
    private let serviceName = "com.iflytek.lookhealth.devicebindings"
    private let accountName = "device_bindings_v1"
    
    /// 保存设备绑定列表
    func saveBindings(_ bindings: [DeviceBinding]) throws {
        let data = try JSONEncoder().encode(bindings)
        
        // 先删除旧项
        delete()
        
        // 添加新项
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// 读取设备绑定列表
    func loadBindings() throws -> [DeviceBinding] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return []
        }
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        
        return try JSONDecoder().decode([DeviceBinding].self, from: data)
    }
    
    /// 删除
    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
}
```

### 9.3 HealthKit数据安全

HealthKit本身由系统加密存储，我们的代码只在内存中处理数据：
- 不缓存健康数据到磁盘（除非是用户明确保存的饮食记录等业务数据）
- AI工具查询的临时健康数据只在本次会话中使用，不落地
- 写入HealthKit的数据通过系统API写入，由系统管理安全

---

## 10. 模块文件结构规划

按照项目现有结构（Features目录下按功能模块组织），新建设备绑定功能模块：

```
SparkClient/Projects/Features/
└── DeviceBinding/                    ← 新模块根目录
    ├── Domain/                       ← 领域层
    │   ├── DeviceBinding.swift       ← 绑定实体
    │   ├── HealthDataSourceType.swift ← 数据源枚举
    │   ├── HealthAuthorizationStatus.swift ← 授权状态枚举
    │   └── DeviceBindingErrors.swift ← 错误定义
    │
    ├── Application/                  ← 应用层（UseCase）
    │   ├── DeviceBindingUseCase.swift
    │   ├── HealthAuthorizationUseCase.swift
    │   └── HealthDataAccessGate.swift ← 访问控制网关
    │
    ├── Infrastructure/               ← 基础设施层
    │   ├── DeviceBindingStore.swift  ← 绑定存储（Keychain实现）
    │   ├── HealthKitAuthorizationStore.swift ← HealthKit封装
    │   └── KeychainHelper.swift      ← Keychain工具
    │
    └── Presentation/                 ← 表示层
        ├── MyDevices/
        │   ├── MyDevicesView.swift           ← 我的设备页
        │   ├── MyDevicesViewModel.swift
        │   └── Components/
        │       ├── DeviceBindingCard.swift   ← 设备卡片组件
        │       └── DeleteConfirmationAlert.swift
        │
        ├── AddDevice/
        │   ├── AddDeviceView.swift           ← 添加设备页
        │   └── AddDeviceViewModel.swift
        │
        ├── MemberSelection/
        │   ├── SwitchBindingMemberSheet.swift ← 切换成员弹窗
        │   └── MemberSelectionRow.swift
        │
        └── PermissionGuide/
            ├── PermissionRevokedSheet.swift  ← 权限异常引导弹窗
            └── PermissionGuideImages.swift   ← 引导图资源引用
```

### 10.1 现有文件修改清单

| 文件路径 | 修改内容 |
|---------|---------|
| `SparkClient/Projects/Core/Health/SparkHealthTool.swift` | 接入HealthDataAccessGate，增加memberId参数，改造授权逻辑 |
| `SparkClient/Projects/Features/Nutrition/Infrastructure/NutritionHealthKitStore.swift` | 接入访问网关 |
| `SparkClient/Projects/Features/MemberContext/Presentation/MemberDetailView.swift` | 增加"数据来源"模块入口 |
| `SparkClient/Projects/App/Sources/App/AppBootstrapper.swift` | 初始化HealthDataAccessGate配置、启动授权状态监听 |
| `SparkClient/Projects/App/Sources/App/FeatureAssemblies.swift` | 注册依赖注入 |
| `SparkClient/Projects/Features/Home/Presentation/...` | 首页健康卡片改造，接入访问检查 |
| `SparkClient/Info.plist` | 确保HealthKit权限描述完整（如果现有已有则不用改） |
| `SparkClient/SparkClient.entitlements` | 确保开启HealthKit能力 |

---

## 11. 测试要点

### 11.1 功能测试用例

| 用例ID | 测试场景 | 前置条件 | 操作步骤 | 预期结果 |
|--------|---------|---------|---------|---------|
| TC-001 | 首次绑定苹果健康到本人 | 1. 从未绑定过<br>2. 有成员"本人" | 1. 进入我的设备→添加设备<br>2. 点击苹果健康的"去同步"<br>3. 选择"本人"<br>4. 在系统弹窗允许授权 | 1. 绑定成功<br>2. 我的设备列表显示苹果健康卡片<br>3. 卡片显示"本人"<br>4. 无"数据异常"标记 |
| TC-002 | 绑定苹果健康时拒绝授权 | 同TC-001 | 1. 触发授权弹窗时点击"不允许" | 1. 绑定记录创建，但状态为.denied<br>2. 卡片显示"数据异常"红色标签 |
| TC-003 | 切换绑定成员 | 苹果健康已绑定本人，有"爸爸"成员 | 1. 点击苹果健康卡片"切换绑定"<br>2. 选择"爸爸" | 1. 切换成功<br>2. 卡片显示绑定给"爸爸"<br>3. 本人不再显示绑定 |
| TC-004 | 解绑设备 | 已绑定苹果健康 | 1. 点击垃圾桶图标<br>2. 点击"解绑"确认 | 1. 卡片从列表消失<br>2. 添加设备页苹果健康显示"去同步" |
| TC-005 | 解绑时点击"再想想" | 已绑定 | 1. 点击垃圾桶<br>2. 点击"再想想" | 弹窗关闭，绑定未解除 |
| TC-006 | 绑定后收回权限 | 已授权绑定苹果健康 | 1. 切到系统设置<br>2. 关闭讯飞晓医的健康权限<br>3. 切回App | 1. 回到App后弹出温馨提示弹窗<br>2. 点击"数据异常"也能弹出引导<br>3. 我的设备卡片显示红色"数据异常" |
| TC-007 | 一个成员不能绑定多个健康账号 | 爸爸已绑定华为运动健康 | 尝试给爸爸绑定苹果健康 | 提示"一个成员只能绑定一个健康账号" |
| TC-008 | 一个数据源不能绑定多个成员 | 苹果健康已绑定本人 | 尝试绑定给爸爸时弹窗确认 | 不确认则不切换，确认后切换成功 |
| TC-009 | App重启后绑定状态保留 | 已绑定苹果健康 | 杀死App重新打开 | 我的设备页仍显示已绑定状态，不需要重新授权 |
| TC-010 | 未绑定成员访问健康数据 | 给未绑定苹果健康的成员（如妈妈） | AI查询妈妈的健康数据 | 返回友好提示"当前成员未绑定健康数据来源"，不崩溃 |
| TC-011 | 未接入数据源置灰 | / | 进入添加设备页点击vivo健康 | 选项置灰，点击提示"暂未开通" |
| TC-012 | 医疗器械选项置灰 | / | 点击血压计 | 提示"医疗器械功能暂未接入" |

### 11.2 边界测试

- 成员列表为空时的绑定流程
- 快速连续点击绑定按钮的防重复处理
- 授权过程中App切后台再回来的状态恢复
- 系统语言为英文/繁体时的本地化适配
- 深色模式下的UI显示
- 不同屏幕尺寸（SE、Pro Max）的布局适配

### 11.3 安全测试

- 检查iCloud备份中是否包含绑定数据（应该不包含）
- 检查控制台日志是否打印健康数据（Release包应该无）
- 卸载重装后绑定数据应该被清除（符合预期）

---

## 12. 本地化字符串清单

所有新增文本需支持多语言，Key命名规范：`device.binding.xxx`

```
// MARK: - 我的设备页
"device.my.title" = "我的设备";
"device.my.account_section" = "账号数据";
"device.my.account_hint" = "一个成员只能绑定一个健康账号";
"device.my.add_button" = "+ 添加设备";
"device.my.no_data" = "暂无绑定设备";
"device.my.no_data_hint" = "点击下方按钮添加健康数据来源";
"device.my.status.synced" = "已同步";
"device.my.status.data_abnormal" = "数据异常";
"device.my.switch_binding" = "切换绑定";

// MARK: - 添加设备页
"device.add.title" = "选择并添加设备";
"device.add.subtitle" = "同步设备数据，为你提供更精准的健康解读服务";
"device.add.go_sync" = "去同步";
"device.add.go_bind" = "去绑定";
"device.all" = "全部";
"device.bp_monitor" = "血压计";
"device.glucometer" = "血糖仪";
"device.source.apple_health.desc" = "支持用户将苹果账号下的健康数据同步至讯飞晓医";
"device.source.huawei_health.desc" = "支持用户将HUAWEI Health账号的健康数据同步至讯飞晓医";
"device.source.vivo_health.desc" = "支持用户将vivo账号下的健康数据同步至讯飞晓医";
"device.source.coros.desc" = "支持用户将COROS账号下的健康数据同步至讯飞晓医";
"device.source.bp_x7.desc" = "讯飞臂筒式血压计 X7";
"device.source.not_available" = "暂未接入，敬请期待";
"device.medical_section" = "医疗器械";

// MARK: - 切换绑定
"device.switch.title" = "切换绑定成员";
"device.switch.bound_tag" = "已绑定";
"device.switch.already_bound_to_other" = "苹果健康当前已绑定给「%@」，是否切换绑定到「%@」？";
"device.switch.member_has_other_binding" = "该成员已绑定其他健康账号，一个成员只能绑定一个健康账号";

// MARK: - 解绑确认
"device.unbind.title" = "解绑设备";
"device.unbind.message" = "是否确认解绑当前设备？";
"device.unbind.confirm" = "解绑";
"device.unbind.cancel" = "再想想";
"device.unbind.success" = "解绑成功";

// MARK: - 权限引导
"device.permission.guide_title" = "温馨提示";
"device.permission.revoked_message" = "无法获取数据，你的苹果健康可能暂无数据产生或系统权限未开启。\n请前往【设置-隐私与安全-健康-讯飞晓医】进行操作。";
"device.permission.got_it" = "知道了";
"device.permission.go_settings" = "去设置";

// MARK: - 成员详情入口
"member.detail.data_source" = "数据来源";
"member.detail.data_source_status.bound" = "已绑定";
"member.detail.data_source_status.unbound" = "未绑定";
"member.detail.data_source_summary.apple" = "苹果健康";
"member.detail.data_source_action.bind" = "去绑定";
"member.detail.data_source_action.manage" = "去管理";

// MARK: - 错误提示
"device.error.healthkit_unavailable" = "当前设备不支持苹果健康";
"device.error.bind_failed" = "绑定失败，请稍后重试";
"device.error.member_load_failed" = "成员列表加载失败，请检查网络";
"device.error.already_bound_self" = "该数据源已绑定给当前成员";
```

---

## 附录A：苹果健康需要申请的权限类型完整清单

### 读取权限（Read Types）

| 权限Identifier | 用途 | 必要性 |
|---------------|------|-------|
| `stepCount` | 步数 | 必须 |
| `distanceWalkingRunning` | 步行+跑步距离 | 必须 |
| `activeEnergyBurned` | 活动能量消耗 | 必须 |
| `basalEnergyBurned` | 基础代谢能量 | 必须 |
| `dietaryEnergyConsumed` | 饮食能量摄入 | 必须 |
| `dietaryProtein` | 蛋白质摄入 | 必须 |
| `dietaryCarbohydrates` | 碳水摄入 | 必须 |
| `dietaryFatTotal` | 脂肪摄入 | 必须 |
| `sleepAnalysis` | 睡眠分析 | 必须 |
| `heartRate` | 心率 | 推荐 |
| `respiratoryRate` | 呼吸频率 | 推荐 |
| `flightsClimbed` | 爬楼层数 | 推荐 |
| `distanceCycling` | 骑行距离 | 推荐 |
| `workoutType` | 健身记录 | 必须 |
| `workoutRouteType` | 运动路线 | 可选 |
| `runningSpeed` | 跑步速度 | 可选 |
| `appleSleepingWristTemperature` | 睡眠手腕温度 | 可选（Apple Watch） |

### 写入权限（Write Types）

| 权限Identifier | 用途 |
|---------------|------|
| `dietaryEnergyConsumed` | 写入用户手动记录的饮食能量 |
| `dietaryProtein` | 写入蛋白质 |
| `dietaryCarbohydrates` | 写入碳水 |
| `dietaryFatTotal` | 写入脂肪 |
| `activeEnergyBurned` | 写入手动记录的活动消耗 |

---

## 附录B：Info.plist 权限描述

确保Info.plist中配置以下权限描述（如果已有需核对文案）：

```xml
<!-- 健康数据读取 -->
<key>NSHealthShareUsageDescription</key>
<string>需要读取您的健康数据（步数、睡眠、运动、心率等），为您提供个性化健康分析服务</string>
<!-- 健康数据写入 -->
<key>NSHealthUpdateUsageDescription</key>
<string>需要将您记录的饮食、运动数据同步到苹果健康</string>
```

---

## 附录C：UI设计图对应说明

本文档界面设计参考提供的5张设计图：

1. **图1 - 我的设备列表页**：展示已绑定的设备卡片、异常标记、切换绑定、删除按钮、添加设备按钮
2. **图2 - 切换绑定成员弹窗**：底部弹窗，成员列表，当前选中成员有蓝色对勾标记
3. **图3 - 选择并添加设备页**：账号数据分组（华为/苹果/vivo/COROS）+ 医疗器械分组，未接入选项置灰
4. **图4 - 解绑确认弹窗**：居中Alert，红色"解绑"按钮
5. **图5 - 权限异常温馨提示**：底部弹窗，包含错误说明、操作路径指引、引导配图、知道了按钮

开发时请严格按照设计图还原视觉效果，包括间距、字体大小、颜色、圆角等细节。

---

## 附录D：开发优先级建议

| 优先级 | 功能点 | 建议工期 |
|-------|-------|---------|
| P0 | 核心数据模型 + Keychain存储 | 0.5天 |
| P0 | HealthKit授权封装 | 0.5天 |
| P0 | DeviceBindingUseCase业务逻辑 | 1天 |
| P0 | 我的设备列表页 + 设备卡片组件 | 1天 |
| P0 | 添加设备页（苹果健康可点击，其他置灰） | 0.5天 |
| P0 | 切换绑定成员弹窗 | 0.5天 |
| P0 | 解绑确认弹窗 + 解绑逻辑 | 0.5天 |
| P0 | 苹果健康完整绑定流程 | 0.5天 |
| P0 | 权限收回异常弹窗 + 状态监听 | 0.5天 |
| P1 | HealthDataAccessGate访问网关 | 1天 |
| P1 | 改造现有SparkHealthTool接入网关 | 1天 |
| P1 | 改造NutritionHealthKitStore接入网关 | 0.5天 |
| P1 | 成员详情页增加数据来源入口 | 0.5天 |
| P1 | 首页健康卡片接入权限检查 | 0.5天 |
| P2 | 引导配图资源添加 | 0.2天 |
| P2 | 深色模式适配 | 0.3天 |
| P2 | 英文/繁体本地化 | 0.5天 |
| P2 | 单元测试 | 1天 |
| **合计** | | **~10天** |

---

**文档结束**

> 本文档由需求分析生成，开发过程中如有疑问请及时沟通确认。