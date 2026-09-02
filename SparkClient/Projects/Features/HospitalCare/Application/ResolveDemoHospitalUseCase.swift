import Foundation

/// CHAT-000054：演示医院解析结果。
enum DemoHospitalResolution: Equatable, Sendable {
    /// 按服务端返回顺序取第一家医院。
    case resolved(HospitalSummary)
    /// 医院目录加载成功，但列表为空（Q31：回退普通对话）。
    case missing
    /// 医院目录加载失败（网络/服务异常且无缓存兜底，Q31：回退普通对话）。
    case failed
}

/// CHAT-000055 Q30：取服务端医院列表第一家作为演示医院——不使用 code、固定 UUID 或名称匹配。
/// 缓存数组保留服务端顺序；命中缓存先返回，过期时后台静默刷新（stale-while-revalidate）。
struct ResolveDemoHospitalUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let logger: any Logger = ConsoleLogger()

    func execute(accountID: Int64, forceRefresh: Bool = false) async -> DemoHospitalResolution {
        if forceRefresh == false, let cached = catalogCache.hospitals(accountID: accountID) {
            if catalogCache.isHospitalsStale(accountID: accountID) {
                scheduleBackgroundRefresh(accountID: accountID)
            }
            return resolveFirst(from: cached)
        }
        do {
            let hospitals = try await catalogCache.singleFlightHospitals(accountID: accountID) {
                try await remoteAPI.listHospitals(page: 1, pageSize: 100).map {
                    HospitalSummary(
                        id: $0.id,
                        code: $0.code ?? "",
                        name: $0.name,
                        shortName: $0.shortName ?? "",
                        introduction: $0.introduction ?? "",
                        status: $0.status
                    )
                }
            }
            return resolveFirst(from: hospitals)
        } catch {
            // 刷新失败继续使用旧缓存（Q31：仅无缓存失败才回退普通对话）。
            if let cached = catalogCache.hospitals(accountID: accountID) {
                return resolveFirst(from: cached)
            }
            logger.warning(
                "hospital.demo.resolve_failed error=\(error.localizedDescription)",
                module: .general
            )
            return .failed
        }
    }

    /// Q30：取列表第一家并记录日志，方便演示联调检查；后台调整首位医院属演示配置行为。
    private func resolveFirst(from hospitals: [HospitalSummary]) -> DemoHospitalResolution {
        guard let first = hospitals.first else {
            logger.warning("hospital.demo.resolve_first empty=true", module: .general)
            return .missing
        }
        logger.info(
            "hospital.demo.resolve_first id=\(first.id.uuidString) name=\(first.name)",
            module: .general
        )
        return .resolved(first)
    }

    /// 后台静默刷新：失败仅记录日志，不影响已返回的缓存结果。
    private func scheduleBackgroundRefresh(accountID: Int64) {
        Task { [remoteAPI, catalogCache, logger] in
            do {
                _ = try await catalogCache.singleFlightHospitals(accountID: accountID) {
                    try await remoteAPI.listHospitals(page: 1, pageSize: 100).map {
                        HospitalSummary(
                            id: $0.id,
                            code: $0.code ?? "",
                            name: $0.name,
                            shortName: $0.shortName ?? "",
                            introduction: $0.introduction ?? "",
                            status: $0.status
                        )
                    }
                }
            } catch {
                logger.warning(
                    "hospital.demo.background_refresh_failed error=\(error.localizedDescription)",
                    module: .general
                )
            }
        }
    }
}
