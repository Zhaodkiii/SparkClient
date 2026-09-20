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

/// CHAT-000055：演示医院优先使用当前演示机构编码；未返回时回退服务端列表第一家。
/// 缓存数组保留服务端顺序；命中缓存先返回，过期时后台静默刷新（stale-while-revalidate）。
struct ResolveDemoHospitalUseCase: Sendable {
    /// 医院 Demo 默认机构：天长市人民医院。
    /// 该值只控制客户端演示入口，不替代服务端医院权限校验。
    static let preferredHospitalCode = "000002"

    let remoteAPI: any HospitalCareRemoteServing
    let catalogCache: HospitalCatalogMemoryCache
    let logger: any Logger = ConsoleLogger()

    func execute(accountID: Int64, forceRefresh: Bool = false) async -> DemoHospitalResolution {
        if forceRefresh == false, let cached = catalogCache.hospitals(accountID: accountID) {
            if catalogCache.isHospitalsStale(accountID: accountID) {
                scheduleBackgroundRefresh(accountID: accountID)
            }
            return resolvePreferred(from: cached)
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
            return resolvePreferred(from: hospitals)
        } catch {
            // 刷新失败继续使用旧缓存（Q31：仅无缓存失败才回退普通对话）。
            if let cached = catalogCache.hospitals(accountID: accountID) {
                return resolvePreferred(from: cached)
            }
            logger.warning(
                "hospital.demo.resolve_failed error=\(error.localizedDescription)",
                module: .general
            )
            return .failed
        }
    }

    private func resolvePreferred(from hospitals: [HospitalSummary]) -> DemoHospitalResolution {
        guard let hospital = hospitals.first(where: { $0.code == Self.preferredHospitalCode }) ?? hospitals.first else {
            logger.warning("hospital.demo.resolve_first empty=true", module: .general)
            return .missing
        }
        logger.info(
            "hospital.demo.resolve id=\(hospital.id.uuidString) name=\(hospital.name) code=\(hospital.code)",
            module: .general
        )
        return .resolved(hospital)
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
