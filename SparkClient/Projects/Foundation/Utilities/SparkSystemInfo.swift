import Foundation
import UIKit

#if canImport(Darwin)
import Darwin
#endif

/// 设备与系统信息，用于 `/api/v1/device/register/` 上报（字段与 SparkService `DeviceRegisterSerializer` 对齐）。
///
/// UIKit / DeviceKit API 在 iOS 18+ 为 `@MainActor`，在 `init` 中一次性采集为普通值，避免在后台线程重复触碰主线程 API。
/// @MainActor 标记：所有成员初始化运行在主线程，规避UIDevice/UIScreen主线隔离编译报错
/// Spark系统设备信息实体：统一采集iOS设备、应用、地域时区相关全量环境信息
@MainActor
struct SparkSystemInfo {
    // MARK: - 设备&应用标识字段
    /// 设备安装唯一ID：钥匙串持久化生成，设备重装APP会重新生成
    let installationDeviceID: String
    /// APP BundleID应用包名，如 cn.Zhaodk.Health
    let bundleIdentifier: String
    /// 应用对外展示版本号(CFBundleShortVersionString)，例：1.5.0
    let appVersion: String
    /// 应用编译构建号(CFBundleVersion)，内部打包迭代版本
    let buildVersion: String
    /// 运行平台固定标识：iOS
    let platform: String

    // MARK: - 系统&硬件机型信息
    /// iOS系统版本号，例：26.5.1
    let systemVersion: String
    /// 设备底层硬件型号编码(原始machine码)：iPhone18,1 这类机型代号
    let deviceModel: String
    /// 设备友好机型名称：iPhone SE(第三代)/iPhone 15等可读名称
    let deviceModelName: String
    /// 用户自定义设备名称：用户在设置-通用里修改的设备名
    let deviceName: String

    // MARK: - 屏幕参数
    /// 屏幕逻辑分辨率字符串：宽×高，如402×874
    let screenSize: String
    /// 屏幕倍率：@2x=2.0 / @3x=3.0
    let screenScale: Double

    // MARK: - 时区、语言、地域
    /// 当前系统时区标识：Asia/Shanghai
    let timeZone: String
    /// 系统首选语言简码：zh/en等
    let languageCode: String
    /// 系统地区码：CN/US/HK 两位国家码
    let regionCode: String

    // MARK: - 环境与地区判定
    /// 是否运行在模拟器环境
    let isSimulator: Bool
    /// 客户端推断的最可信国家二字码，优先regionCode，无则从首选语言判断CN
    let mostLikelyCountryCode: String
    /// 布尔：是否判定为中国大陆地区用户
    let isMostLikelyMainlandChina: Bool

    // MARK: - 构造方法：主线程一次性采集全量设备信息
    init() {
        // 从钥匙串获取/生成全局唯一设备ID
        installationDeviceID = SparkKeychain.getOrCreateDeviceID()
        // 读取工程配置BundleID
        bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        // 读取应用版本号
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        // 读取构建号
        buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        platform = "iOS"
        // 获取本机iOS系统版本
        systemVersion = UIDevice.current.systemVersion

        /// C函数uname获取底层硬件machine原始编码，用来解析deviceModel机型代号
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        // 遍历结构体字节，拼接字符串得到原始硬件型号
        deviceModel = mirror.children.reduce("") { acc, elem in
            guard let v = elem.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(bitPattern: v)))
        }

        /// 通过Device三方机型库映射原始编码→可读机型名称
        let device = Device.current
        switch device {
        case .unknown:
            deviceModelName = ""
        case .simulator(let simulatedDevice):
            // 模拟器场景：读取模拟设备机型名
            if case .unknown = simulatedDevice {
                deviceModelName = ""
            } else {
                deviceModelName = simulatedDevice.safeDescription
            }
        default:
            // 真机场景赋值友好机型名
            deviceModelName = device.safeDescription
        }

        // 获取用户自定义设备昵称
        deviceName = UIDevice.current.name

        // 屏幕宽高拼接为 "宽×高" 格式字符串
        let size = UIScreen.main.bounds.size
        screenSize = "\(Int(size.width))×\(Int(size.height))"
        screenScale = Double(UIScreen.main.scale)

        // 当前系统时区标识
        timeZone = TimeZone.current.identifier

        /// iOS16+与低版本区分Locale API，分别读取语言、地区码
        if #available(iOS 16.0, *) {
            languageCode = Locale.current.language.languageCode?.identifier ?? ""
            regionCode = Locale.current.region?.identifier ?? ""
        } else {
            languageCode = Locale.current.languageCode ?? ""
            regionCode = Locale.current.regionCode ?? ""
        }

        /// 编译期宏判断是否模拟器
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        isSimulator = false
        #endif

        /// 自动推断用户所在国家码：
        /// 1.优先使用系统RegionCode；2.无地区码则从系统首选语言匹配简体中文赋值CN
        let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !region.isEmpty {
            mostLikelyCountryCode = region
        } else {
            let langs = Locale.preferredLanguages.map { $0.lowercased() }
            if langs.contains(where: { $0.hasPrefix("zh-hans-cn") || $0.hasPrefix("zh-cn") }) {
                mostLikelyCountryCode = "CN"
            } else {
                mostLikelyCountryCode = ""
            }
        }

        // 判断是否中国大陆用户
        isMostLikelyMainlandChina = mostLikelyCountryCode == "CN"
    }

    /// 全局单例：项目全局统一使用一份设备环境信息，避免重复采集
    static let shared = SparkSystemInfo()
}
