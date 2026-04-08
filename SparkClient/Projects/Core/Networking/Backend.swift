import Foundation

/// 统一网络门面。
/// 对上层隐藏具体 API 细节，仅暴露按业务域拆分的 API 客户端。
final class Backend {
    let baseURL: URL
    let configuration: SparkBackendConfiguration

    let auth: SparkAuthAPI
    let otp: SparkOTPAPI
    let device: SparkDeviceAPI
    let deactivation: SparkDeactivationAPI
    let aiConfig: SparkAIConfigAPI
    let chat: SparkChatRemoteAPI
    let medicalMembers: SparkMedicalMemberAPI
    let medicalQuery: SparkMedicalQueryAPI
    let medicalResources: SparkMedicalResourceAPI
    let medicalWorkflow: SparkMedicalWorkflowAPI
    let files: SparkFileAPI
    let oss: SparkOSSAPI
    let ocr: SparkOCRAPI
    let deviceCache: DeviceCache

    init(
        baseURL: URL,
        transport: SparkNetworkTransport = URLSessionNetworkTransport(),
        gate: SerialRequestGate = SerialRequestGate(),
        deviceCache: DeviceCache = DeviceCache(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        authProvider: AuthTokenProvider? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.baseURL = baseURL
        if let level = deviceCache.persistedLogLevel {
            SparkLogger.logLevel = level
        }

        let etagInterceptor = ETagHTTPInterceptor(store: deviceCache, logger: logger)
        let engine = SparkNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: gate,
            etagInterceptor: etagInterceptor,
            retryPolicy: retryPolicy,
            authProvider: authProvider,
            deviceCache: deviceCache,
            logger: logger
        )
        let configuration = SparkBackendConfiguration(engine: engine, deviceCache: deviceCache, logger: logger)
        self.configuration = configuration
        self.deviceCache = deviceCache
        self.auth = SparkAuthAPI(configuration: configuration)
        self.otp = SparkOTPAPI(configuration: configuration)
        self.device = SparkDeviceAPI(configuration: configuration)
        self.deactivation = SparkDeactivationAPI(configuration: configuration)
        self.aiConfig = SparkAIConfigAPI(configuration: configuration)
        self.chat = SparkChatRemoteAPI(configuration: configuration)
        self.medicalMembers = SparkMedicalMemberAPI(configuration: configuration)
        self.medicalQuery = SparkMedicalQueryAPI(configuration: configuration)
        self.medicalResources = SparkMedicalResourceAPI(configuration: configuration)
        self.medicalWorkflow = SparkMedicalWorkflowAPI(configuration: configuration)
        self.files = SparkFileAPI(configuration: configuration)
        self.oss = SparkOSSAPI(configuration: configuration)
        self.ocr = SparkOCRAPI(configuration: configuration)

        logger.info(SparkNetworkingStrings.Backend.initialized)
    }

    init(configuration: SparkBackendConfiguration) {
        self.baseURL = configuration.engine.serviceBaseURL
        self.configuration = configuration
        self.deviceCache = configuration.deviceCache
        self.auth = SparkAuthAPI(configuration: configuration)
        self.otp = SparkOTPAPI(configuration: configuration)
        self.device = SparkDeviceAPI(configuration: configuration)
        self.deactivation = SparkDeactivationAPI(configuration: configuration)
        self.aiConfig = SparkAIConfigAPI(configuration: configuration)
        self.chat = SparkChatRemoteAPI(configuration: configuration)
        self.medicalMembers = SparkMedicalMemberAPI(configuration: configuration)
        self.medicalQuery = SparkMedicalQueryAPI(configuration: configuration)
        self.medicalResources = SparkMedicalResourceAPI(configuration: configuration)
        self.medicalWorkflow = SparkMedicalWorkflowAPI(configuration: configuration)
        self.files = SparkFileAPI(configuration: configuration)
        self.oss = SparkOSSAPI(configuration: configuration)
        self.ocr = SparkOCRAPI(configuration: configuration)

        configuration.logger.info(SparkNetworkingStrings.Backend.initialized)
    }

    func tokenProvider() -> AuthTokenProvider {
        configuration.engine.tokenProvider()
    }

    func configure(logLevel: LogLevel, persist: Bool = true) {
        SparkLogger.logLevel = logLevel
        if persist {
            deviceCache.cache(logLevel: logLevel)
        }
    }
}
