import CoreBluetooth
import Foundation

enum NearbyShareBLE {
    #if DEBUG
    static let serviceUUID = CBUUID(string: "A8F3C912-5E4D-4B9A-8C01-2D9E7B6F4A21")
    static let beaconCharacteristicUUID = CBUUID(string: "B7E2D803-6F5C-4D3A-9E02-1C8F5A6B3D40")
    static let payloadCharacteristicUUID = CBUUID(string: "C6D1E904-7A6E-5E4B-AF13-2D0F6B7C5E51")
    #else
    static let serviceUUID = CBUUID(string: "D4E5F607-8A9B-4C2D-BE03-3F1A8C9D6E72")
    static let beaconCharacteristicUUID = CBUUID(string: "E5F60718-9BAC-4D3E-CF14-401B9D0E7F83")
    static let payloadCharacteristicUUID = CBUUID(string: "F6071829-ABCD-4E4F-DF25-512C0E1F8A94")
    #endif

    static let maxPayloadBytes = 1024
    static let peerStaleInterval: TimeInterval = 15
    static let peerPruneInterval: TimeInterval = 2
    static let maxVisiblePeers = 20
    static let receiveMode = "receive"
    static let shareType = "member_share"
}
