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
}
