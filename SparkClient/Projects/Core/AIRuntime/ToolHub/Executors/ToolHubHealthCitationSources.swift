import Foundation

extension ToolHub {
    private struct HealthCitationSource: Sendable {
        let title: String
        let url: String
        let summary: String
        let sourceName: String
        let keywords: [String]
    }

    private var healthCitationCatalog: [HealthCitationSource] {
        [
            HealthCitationSource(
                title: "国家卫生健康委员会 NHC",
                url: "http://www.nhc.gov.cn/",
                summary: "国家卫生健康政策、临床指南、疾病防控和健康科普信息。",
                sourceName: "NHC",
                keywords: ["中国", "国家", "临床指南", "诊疗", "就医", "慢病", "健康管理", "公共卫生"]
            ),
            HealthCitationSource(
                title: "中国疾病预防控制中心 CDC",
                url: "http://www.chinacdc.cn/",
                summary: "传染病、慢病监测、健康风险和疾病预防控制信息。",
                sourceName: "中国 CDC",
                keywords: ["传染病", "预防", "疫苗", "感染", "慢病", "公共卫生", "流感", "新冠"]
            ),
            HealthCitationSource(
                title: "国家药品监督管理局 NMPA",
                url: "https://www.nmpa.gov.cn/",
                summary: "药品、医疗器械、化妆品监管及安全信息。",
                sourceName: "NMPA",
                keywords: ["药", "药物", "用药", "副作用", "不良反应", "药品", "医疗器械", "审批", "监管"]
            ),
            HealthCitationSource(
                title: "中华医学会",
                url: "https://www.cma.org.cn/",
                summary: "中国医学专业组织和专业分会指南、共识与继续医学教育信息。",
                sourceName: "CMA",
                keywords: ["中华医学会", "指南", "专家共识", "高血压", "血脂", "糖尿病", "诊疗"]
            ),
            HealthCitationSource(
                title: "World Health Organization WHO",
                url: "https://www.who.int/",
                summary: "全球公共卫生、慢病防控、营养、BMI 和疾病预防信息。",
                sourceName: "WHO",
                keywords: ["who", "世界卫生组织", "慢病", "营养", "bmi", "肥胖", "预防", "公共卫生", "健康"]
            ),
            HealthCitationSource(
                title: "National Institutes of Health NIH",
                url: "https://www.nih.gov/",
                summary: "综合医学科普、健康信息、研究和临床试验入口。",
                sourceName: "NIH",
                keywords: ["nih", "医学科普", "研究", "临床试验", "症状", "疾病", "健康信息"]
            ),
            HealthCitationSource(
                title: "MedlinePlus",
                url: "https://medlineplus.gov/",
                summary: "面向公众的疾病、检查、药物、用药指导和相互作用信息。",
                sourceName: "MedlinePlus",
                keywords: ["medlineplus", "药物", "用药", "相互作用", "症状", "检查", "患者教育", "疾病"]
            ),
            HealthCitationSource(
                title: "U.S. Food and Drug Administration FDA",
                url: "https://www.fda.gov/",
                summary: "药物审批、安全通报、药物标签、医疗器械和食品安全信息。",
                sourceName: "FDA",
                keywords: ["fda", "药", "药物", "用药", "标签", "副作用", "安全", "食品", "医疗器械"]
            ),
            HealthCitationSource(
                title: "European Medicines Agency EMA",
                url: "https://www.ema.europa.eu/",
                summary: "欧洲药品监管、安全信息和药物评估报告。",
                sourceName: "EMA",
                keywords: ["ema", "欧洲药品", "药物", "用药", "药品监管", "安全", "评估报告"]
            ),
            HealthCitationSource(
                title: "United States Pharmacopeia USP",
                url: "https://www.usp.org/",
                summary: "药物标准、质量规范和药品质量相关信息。",
                sourceName: "USP",
                keywords: ["usp", "药典", "药物标准", "质量", "药品质量", "规范"]
            ),
            HealthCitationSource(
                title: "WHO Essential Medicines",
                url: "https://www.who.int/medicines/",
                summary: "世界卫生组织基本药物、用药指南和药物安全信息入口。",
                sourceName: "WHO Essential Medicines",
                keywords: ["基本药物", "essential medicines", "用药", "药物", "药物安全", "指南"]
            ),
            HealthCitationSource(
                title: "American Heart Association AHA",
                url: "https://www.heart.org/",
                summary: "心血管健康、血压、血脂、卒中和生活方式建议。",
                sourceName: "AHA",
                keywords: ["aha", "心脏", "心血管", "血压", "高血压", "血脂", "胆固醇", "卒中", "中风"]
            ),
            HealthCitationSource(
                title: "European Society of Cardiology ESC",
                url: "https://www.escardio.org/",
                summary: "欧洲心血管疾病指南、教育和专业资源。",
                sourceName: "ESC",
                keywords: ["esc", "心血管", "心脏", "血压", "高血压", "血脂", "指南", "冠心病"]
            ),
            HealthCitationSource(
                title: "American Diabetes Association ADA",
                url: "https://diabetes.org/",
                summary: "糖尿病、血糖、饮食、运动和并发症管理信息。",
                sourceName: "ADA",
                keywords: ["ada", "糖尿病", "血糖", "胰岛素", "糖化", "a1c", "饮食", "控糖"]
            ),
            HealthCitationSource(
                title: "International Diabetes Federation IDF",
                url: "https://idf.org/",
                summary: "国际糖尿病指南、糖尿病流行病学和患者教育资源。",
                sourceName: "IDF",
                keywords: ["idf", "糖尿病", "血糖", "胰岛素", "糖化", "控糖", "指南"]
            ),
            HealthCitationSource(
                title: "National Heart, Lung, and Blood Institute NHLBI",
                url: "https://www.nhlbi.nih.gov/",
                summary: "心脏、肺、血液疾病及睡眠健康信息。",
                sourceName: "NHLBI",
                keywords: ["nhlbi", "心脏", "肺", "血液", "血压", "血脂", "睡眠", "哮喘"]
            ),
            HealthCitationSource(
                title: "American Thoracic Society ATS",
                url: "https://www.thoracic.org/",
                summary: "呼吸系统疾病、肺部健康和专业指南资源。",
                sourceName: "ATS",
                keywords: ["ats", "呼吸", "肺", "咳嗽", "哮喘", "copd", "慢阻肺", "气短"]
            ),
            HealthCitationSource(
                title: "European Respiratory Society ERS",
                url: "https://www.ersnet.org/",
                summary: "欧洲呼吸系统疾病指南、教育和研究资源。",
                sourceName: "ERS",
                keywords: ["ers", "呼吸", "肺", "哮喘", "copd", "慢阻肺", "咳嗽", "气短"]
            ),
            HealthCitationSource(
                title: "National Kidney Foundation NKF",
                url: "https://www.kidney.org/",
                summary: "肾脏疾病、eGFR、尿蛋白、透析和肾脏健康教育。",
                sourceName: "NKF",
                keywords: ["nkf", "肾", "肾脏", "肌酐", "egfr", "尿蛋白", "透析", "肾病"]
            ),
            HealthCitationSource(
                title: "National Cancer Institute NCI",
                url: "https://www.cancer.gov/",
                summary: "肿瘤、筛查、治疗、预防和患者教育信息。",
                sourceName: "NCI",
                keywords: ["nci", "癌", "肿瘤", "筛查", "化疗", "放疗", "恶性", "结节"]
            ),
            HealthCitationSource(
                title: "National Institute for Health and Care Excellence NICE",
                url: "https://www.nice.org.uk/",
                summary: "多学科疾病管理指南、临床路径和卫生技术评估。",
                sourceName: "NICE",
                keywords: ["nice", "指南", "临床路径", "疾病管理", "治疗建议", "诊疗", "英国"]
            )
        ]
    }

    private var defaultHealthCitationSource: HealthCitationSource {
        HealthCitationSource(
            title: "World Health Organization WHO",
            url: "https://www.who.int/",
            summary: "全球公共卫生、疾病预防、健康促进和医学健康信息的权威入口。",
            sourceName: "WHO",
            keywords: ["健康", "医疗", "疾病", "预防", "公共卫生"]
        )
    }

    func runInsertHealthCitationSources(
        invocation: ToolInvocation,
        context: ToolExecutionContext
    ) -> ToolExecutionResult {
        let query = (invocation.arguments["query"] ?? invocation.arguments["keyword"] ?? invocation.arguments["topic"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = citationKeywords(from: invocation, query: query)

        let limit = citationLimit(from: invocation.arguments["limit"])
        let matched = matchedHealthCitationSources(query: query, keywords: keywords, limit: limit)
        let references = matched.map { source in
            ChatSearchSummaryReference(
                title: source.title,
                url: source.url,
                snippet: source.summary,
                sourceName: source.sourceName
            )
        }
        let displayKeywords = keywords.isEmpty ? splitCitationKeywords(query) : keywords
        let fallbackKeywords = displayKeywords.isEmpty ? ["健康", "医疗", "引用来源"] : displayKeywords
        let payload = ChatSearchSummaryCardPayload(
            providerName: "权威健康引用来源",
            query: query.isEmpty ? fallbackKeywords.joined(separator: " ") : query,
            keywords: Array(fallbackKeywords.prefix(12)),
            references: references,
            totalEstimatedMatches: matched.count
        )
        let lines = references.enumerated().map { index, item in
            "[\(index + 1)] \(item.title)\nURL: \(item.url)\n\(item.snippet ?? "")"
        }
        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: "已插入健康/医疗信息引用来源：\n\(lines.joined(separator: "\n\n"))",
            sensitive: false,
            shouldBypassModel: false,
            sideEffects: [.searchSummary(payload)]
        ).withToolCallID(normalizedToolCallID(from: context))
    }

    private func citationKeywords(from invocation: ToolInvocation, query: String) -> [String] {
        var values: [String] = []
        if let raw = invocation.arguments["keywords"] ?? invocation.arguments["keyword"] {
            values.append(contentsOf: splitCitationKeywords(raw))
        }
        values.append(contentsOf: splitCitationKeywords(query))
        var seen = Set<String>()
        return values.filter { keyword in
            let key = keyword.lowercased()
            guard key.isEmpty == false, seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func splitCitationKeywords(_ raw: String) -> [String] {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]\"'"))
            .components(separatedBy: CharacterSet(charactersIn: " ,，、/;；\n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { $0.isEmpty == false }
    }

    private func citationLimit(from raw: String?) -> Int {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 8
        }
        return min(max(value, 3), 12)
    }

    private func matchedHealthCitationSources(query: String, keywords: [String], limit: Int) -> [HealthCitationSource] {
        let searchText = ([query] + keywords).joined(separator: " ").lowercased()
        let scored = healthCitationCatalog.map { source -> (source: HealthCitationSource, score: Int) in
            var score = 0
            for keyword in source.keywords {
                if searchText.contains(keyword.lowercased()) {
                    score += 4
                }
            }
            if searchText.contains(source.sourceName.lowercased()) || searchText.contains(source.title.lowercased()) {
                score += 6
            }
            return (source, score)
        }
        let matches = scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.source.title < rhs.source.title
                }
                return lhs.score > rhs.score
            }
            .map(\.source)
        if matches.isEmpty == false {
            return Array(matches.prefix(limit))
        }
        return [defaultHealthCitationSource]
    }
}
