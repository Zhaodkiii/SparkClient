import Foundation

/// 引导卡片 UI 预览与测试 fixture（仅 DEBUG 预览 / 单测使用，不进入业务链路）。
enum ChatGuideCardPreviewFixtures {
    static var fullPayload: ChatGuideCardPayload {
        ChatGuideCardPayload(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_787_300_000),
            memberID: 42,
            metricSections: [
                ChatGuideMetricSection(
                    id: "movement",
                    category: .movement,
                    title: "运动数据",
                    subtitle: "今日 · 最近更新 08:30",
                    items: [
                        ChatGuideMetricItem(id: "steps", title: "步数", valueText: "10000", unitText: "步", tintName: "green"),
                        ChatGuideMetricItem(id: "calories", title: "热量消耗", valueText: "240", unitText: "千卡", tintName: "orange")
                    ],
                    chart: ChatGuideMiniChart(normalizedValues: [0.15, 0.55, 0.8, 1.0, 0.55, 0.1, 0.35, 0.15, 0.3]),
                    state: .ready
                ),
                ChatGuideMetricSection(
                    id: "body",
                    category: .bodyManagement,
                    title: "身材管理",
                    subtitle: "最近 90 天",
                    items: [
                        ChatGuideMetricItem(id: "weight", title: "体重", valueText: "68.4", unitText: "kg", tintName: "blue"),
                        ChatGuideMetricItem(id: "bmi", title: "BMI", valueText: "22.1", tintName: "purple"),
                        ChatGuideMetricItem(id: "bodyFat", title: "体脂率", valueText: "18.6", unitText: "%", tintName: "orange")
                    ],
                    state: .ready
                ),
                ChatGuideMetricSection(
                    id: "nutrition",
                    category: .nutrition,
                    title: "饮食营养",
                    subtitle: "今日 · 目标 1800 千卡",
                    items: [
                        ChatGuideMetricItem(id: "eaten", title: "已食用", valueText: "1260", unitText: "千卡", tintName: "green"),
                        ChatGuideMetricItem(id: "remaining", title: "剩余", valueText: "540", unitText: "千卡", tintName: "orange"),
                        ChatGuideMetricItem(id: "burned", title: "已消耗", valueText: "240", unitText: "千卡", tintName: "red")
                    ],
                    state: .ready
                ),
                ChatGuideMetricSection(
                    id: "medical",
                    category: .medical,
                    title: "医疗数据",
                    subtitle: "当前成员 · 已同步",
                    items: [
                        ChatGuideMetricItem(id: "medicalCases", title: "病历", valueText: "3", unitText: "份", tintName: "blue"),
                        ChatGuideMetricItem(id: "healthExams", title: "体检", valueText: "2", unitText: "份", tintName: "green"),
                        ChatGuideMetricItem(id: "examReports", title: "检查报告", valueText: "5", unitText: "份", tintName: "orange"),
                        ChatGuideMetricItem(id: "medicationPlans", title: "服药计划", valueText: "1", unitText: "个进行中", tintName: "purple")
                    ],
                    state: .ready
                )
            ],
            questions: [
                ChatGuideQuestion(
                    id: "tcm_medicine_precautions",
                    title: "使用中成药有哪些注意事项?",
                    prompt: "请用通俗易懂的方式科普：使用中成药有哪些注意事项？包括适用人群、禁忌、与西药同服、何时就医。",
                    category: "popular_science"
                ),
                ChatGuideQuestion(
                    id: "astragalus_suitable_groups",
                    title: "黄芪适合哪些人群服用?",
                    prompt: "请用通俗易懂的方式科普：黄芪适合哪些人群服用？包括功效、适用人群、禁忌与日常用法。",
                    category: "popular_science"
                ),
                ChatGuideQuestion(
                    id: "lactose_intolerance_handling",
                    title: "乳糖不耐受如何处理?",
                    prompt: "请用通俗易懂的方式科普：乳糖不耐受应如何处理？包括成因、症状识别、饮食建议与何时就医。",
                    category: "popular_science"
                )
            ]
        )
    }

    static var emptyPayload: ChatGuideCardPayload {
        ChatGuideCardPayload(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1_787_300_000),
            memberID: nil,
            metricSections: [
                ChatGuideMetricSection(
                    id: "movement",
                    category: .movement,
                    title: "运动数据",
                    action: ChatGuideMetricAction(
                        kind: .bindHealth,
                        title: "去绑定"
                    ),
                    state: .unauthorized
                ),
                ChatGuideMetricSection(
                    id: "body",
                    category: .bodyManagement,
                    title: "身材管理",
                    subtitle: "最近 90 天",
                    state: .empty
                ),
                ChatGuideMetricSection(
                    id: "nutrition",
                    category: .nutrition,
                    title: "饮食营养",
                    state: .empty
                ),
                ChatGuideMetricSection(
                    id: "medical",
                    category: .medical,
                    title: "医疗数据",
                    state: .empty
                )
            ],
            questions: ChatGuideQuestionPreset.phaseOne
        )
    }
}
