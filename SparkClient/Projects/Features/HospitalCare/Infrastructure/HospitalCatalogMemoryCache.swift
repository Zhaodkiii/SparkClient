import Foundation

/// 账号隔离的医院目录内存缓存：命中立即返回，后台可静默刷新（stale-while-revalidate）。
/// nonisolated：内部已用 NSLock 保证线程安全，允许统一消息投影器等非 MainActor 上下文读取。
nonisolated final class HospitalCatalogMemoryCache: @unchecked Sendable {
    private struct Entry<Value> {
        let value: Value
        let storedAt: Date
    }

    /// CHAT-000055：超过该间隔的缓存视为 stale——命中仍先返回，但应触发后台静默刷新。
    let stalenessInterval: TimeInterval

    private let lock = NSLock()
    private var hospitals: [Int64: Entry<[HospitalSummary]>] = [:]
    private var departments: [String: Entry<[HospitalDepartmentSummary]>] = [:]
    private var agents: [String: Entry<[HospitalAgentPublicDTO]>] = [:]
    private var agentDetails: [String: Entry<HospitalAgentPublicDTO>] = [:]
    private var inFlightHospitals: [Int64: Task<[HospitalSummary], Error>] = [:]

    init(stalenessInterval: TimeInterval = 300) {
        self.stalenessInterval = stalenessInterval
    }

    func hospitals(accountID: Int64) -> [HospitalSummary]? {
        withLock { hospitals[accountID]?.value }
    }

    func isHospitalsStale(accountID: Int64, now: Date = Date()) -> Bool {
        withLock { isStale(hospitals[accountID], now: now) }
    }

    func storeHospitals(_ value: [HospitalSummary], accountID: Int64) {
        withLock {
            hospitals[accountID] = Entry(value: value, storedAt: Date())
        }
    }

    func departments(accountID: Int64, hospitalID: UUID) -> [HospitalDepartmentSummary]? {
        withLock { departments[departmentKey(accountID: accountID, hospitalID: hospitalID)]?.value }
    }

    func isDepartmentsStale(accountID: Int64, hospitalID: UUID, now: Date = Date()) -> Bool {
        withLock { isStale(departments[departmentKey(accountID: accountID, hospitalID: hospitalID)], now: now) }
    }

    func storeDepartments(_ value: [HospitalDepartmentSummary], accountID: Int64, hospitalID: UUID) {
        withLock {
            departments[departmentKey(accountID: accountID, hospitalID: hospitalID)] = Entry(value: value, storedAt: Date())
        }
    }

    /// CHAT-000055：智能体目录（无筛选的完整列表）缓存读写入口，供 stale-while-revalidate。
    func agents(accountID: Int64, hospitalID: UUID) -> [HospitalAgentPublicDTO]? {
        withLock { agents[agentKey(accountID: accountID, hospitalID: hospitalID)]?.value }
    }

    func isAgentsStale(accountID: Int64, hospitalID: UUID, now: Date = Date()) -> Bool {
        withLock { isStale(agents[agentKey(accountID: accountID, hospitalID: hospitalID)], now: now) }
    }

    func storeAgents(_ value: [HospitalAgentPublicDTO], accountID: Int64, hospitalID: UUID) {
        withLock {
            agents[agentKey(accountID: accountID, hospitalID: hospitalID)] = Entry(value: value, storedAt: Date())
        }
    }

    /// CHAT-000055：医生详情（agent detail）缓存读写入口，供 stale-while-revalidate。
    func agentDetail(agentID: UUID, accountID: Int64) -> HospitalAgentPublicDTO? {
        withLock { agentDetails[agentDetailKey(agentID: agentID, accountID: accountID)]?.value }
    }

    func isAgentDetailStale(agentID: UUID, accountID: Int64, now: Date = Date()) -> Bool {
        withLock { isStale(agentDetails[agentDetailKey(agentID: agentID, accountID: accountID)], now: now) }
    }

    func storeAgentDetail(_ value: HospitalAgentPublicDTO, accountID: Int64) {
        withLock {
            agentDetails[agentDetailKey(agentID: value.id, accountID: accountID)] = Entry(value: value, storedAt: Date())
        }
    }

    func singleFlightHospitals(
        accountID: Int64,
        operation: @escaping @Sendable () async throws -> [HospitalSummary]
    ) async throws -> [HospitalSummary] {
        enum Resolution {
            case existing(Task<[HospitalSummary], Error>)
            case started(Task<[HospitalSummary], Error>)
        }

        let resolution = withLock { () -> Resolution in
            if let existing = inFlightHospitals[accountID] {
                return .existing(existing)
            }
            let task = Task { try await operation() }
            inFlightHospitals[accountID] = task
            return .started(task)
        }

        switch resolution {
        case .existing(let task):
            return try await task.value
        case .started(let task):
            defer {
                withLock { inFlightHospitals[accountID] = nil }
            }
            let value = try await task.value
            storeHospitals(value, accountID: accountID)
            return value
        }
    }

    func clearAccount(_ accountID: Int64) {
        withLock {
            hospitals[accountID] = nil
            let prefix = "\(accountID)."
            departments = departments.filter { $0.key.hasPrefix(prefix) == false }
            agents = agents.filter { $0.key.hasPrefix(prefix) == false }
            agentDetails = agentDetails.filter { $0.key.hasPrefix(prefix) == false }
        }
    }

    func clearAll() {
        withLock {
            hospitals.removeAll()
            departments.removeAll()
            agents.removeAll()
            agentDetails.removeAll()
            inFlightHospitals.removeAll()
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func isStale<Value>(_ entry: Entry<Value>?, now: Date) -> Bool {
        guard let entry else { return true }
        return now.timeIntervalSince(entry.storedAt) >= stalenessInterval
    }

    private func departmentKey(accountID: Int64, hospitalID: UUID) -> String {
        "\(accountID).dept.\(hospitalID.uuidString)"
    }

    private func agentKey(accountID: Int64, hospitalID: UUID) -> String {
        "\(accountID).agents.\(hospitalID.uuidString)"
    }

    private func agentDetailKey(agentID: UUID, accountID: Int64) -> String {
        "\(accountID).agent.\(agentID.uuidString)"
    }
}
