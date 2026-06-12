import Foundation

/// 药箱页面模式（工单 MEDICINE-CABINET-000005）
/// - `family`：家庭药箱，汇总创建者名下全部成员药品与公共药品，展示人员筛选
/// - `personal`：个人药箱，仅加载当前成员的药箱数据，隐藏人员筛选
enum MedicineBoxMode: Equatable, Sendable {
    case family
    case personal
}
