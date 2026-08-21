#if canImport(XCTest)
import Foundation
import XCTest

/// 引导卡片滑块类别 → 独立模块页映射测试（CHAT-000025 v2：直跳各模块页面）：
/// - 运动 → 运动健康模块（FitnessHomeView）
/// - 饮食 → 饮食营养模块（NutritionHomeView）
/// - 身材 / 医疗 → 经典健康首页（HealthHomeView）
final class ChatGuideHomeModuleMappingTests: XCTestCase {
    func testRecommendedCategoryToModuleMapping() {
        XCTAssertEqual(ChatGuideMetricCategory.movement.guideHomeModule, .fitness)
        XCTAssertEqual(ChatGuideMetricCategory.nutrition.guideHomeModule, .nutrition)
        XCTAssertEqual(ChatGuideMetricCategory.bodyManagement.guideHomeModule, .healthHome)
        XCTAssertEqual(ChatGuideMetricCategory.medical.guideHomeModule, .healthHome)
    }

    func testEveryCategoryHasModule() {
        // 映射穷举（新增类别未映射会编译失败），每个类别都必须落到一个合法模块
        let allModules: Set<ChatGuideHomeModule> = [.fitness, .nutrition, .healthHome]
        for category in [ChatGuideMetricCategory.movement, .bodyManagement, .nutrition, .medical] {
            XCTAssertTrue(allModules.contains(category.guideHomeModule))
        }
    }
}
#endif
