import SwiftUI

struct HospitalCareFeatureDependencies {
    let remoteAPI: HospitalCareRemoteAPI
    let catalogCache: HospitalCatalogMemoryCache
    let scopeStore: HospitalConversationScopeStore
    let loadDirectory: LoadHospitalAgentDirectoryUseCase
    let resolveDemoHospital: ResolveDemoHospitalUseCase
    let resolveOrCreate: ResolveOrCreateHospitalConversationUseCase
    let resolveScope: ResolveHospitalConversationScopeUseCase
    let hydrateScopes: HydrateHospitalConversationScopesUseCase
    let loadDoctorProfile: LoadHospitalDoctorProfileUseCase
    /// CHAT-000055：会话 context（能力 + 知识 Manifest）回源。
    let fetchContext: FetchHospitalConversationContextUseCase
    /// CHAT-000055：医院知识只读同步 coordinator。
    let knowledgeSync: HospitalKnowledgeSyncCoordinator
    /// CHAT-000055：医院知识本地只读仓库。
    let knowledgeRepository: any HospitalKnowledgeRepository
}

private struct HospitalCareDependenciesKey: EnvironmentKey {
    static let defaultValue: HospitalCareFeatureDependencies? = nil
}

extension EnvironmentValues {
    var hospitalCare: HospitalCareFeatureDependencies? {
        get { self[HospitalCareDependenciesKey.self] }
        set { self[HospitalCareDependenciesKey.self] = newValue }
    }
}
