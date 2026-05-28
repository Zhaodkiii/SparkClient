import Foundation
import UIKit

#if canImport(Darwin)
import Darwin
#endif

/// 设备与系统信息，用于 `/api/v1/device/register/` 上报（字段与 SparkService `DeviceRegisterSerializer` 对齐）。
nonisolated struct SparkSystemInfo {
    var installationDeviceID: String { SparkKeychain.getOrCreateDeviceID() }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    var platform: String { "iOS" }

    var systemVersion: String {
        UIDevice.current.systemVersion
    }

    var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce("") { acc, elem in
            guard let v = elem.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(bitPattern: v)))
        }
    }

    var deviceModelName: String {
        UIDevice.current.model
    }

    var deviceName: String {
        UIDevice.current.name
    }

    var screenSize: String {
        let size = UIScreen.main.bounds.size
        return "\(Int(size.width))×\(Int(size.height))"
    }

    var screenScale: Double {
        Double(UIScreen.main.scale)
    }

    var timeZone: String {
        TimeZone.current.identifier
    }

    var languageCode: String {
        if #available(iOS 16.0, *) {
            return Locale.current.language.languageCode?.identifier ?? ""
        }
        return Locale.current.languageCode ?? ""
    }

    var regionCode: String {
        if #available(iOS 16.0, *) {
            return Locale.current.region?.identifier ?? ""
        }
        return Locale.current.regionCode ?? ""
    }

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// 返回应用最可能的 ISO 3166-1 alpha-2 国家/地区标识，例如 "CN"、"US"、"HK"。
    /// 仅基于客户端本机信息推断，不依赖服务端。
    var mostLikelyCountryCode: String {
        let region = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if region.isEmpty == false {
            return region
        }

        // region 为空时，尝试从首选语言中强判中国大陆简体中文
        let langs = Locale.preferredLanguages.map { $0.lowercased() }
        if langs.contains(where: { $0.hasPrefix("zh-hans-cn") || $0.hasPrefix("zh-cn") }) {
            return "CN"
        }

        // 兜底：无法判断时返回空字符串（上层应保守处理，例如入口不展示）
        return ""
    }

    /// 是否最可能位于中国大陆。
    var isMostLikelyMainlandChina: Bool {
        mostLikelyCountryCode == "CN"
    }
}
