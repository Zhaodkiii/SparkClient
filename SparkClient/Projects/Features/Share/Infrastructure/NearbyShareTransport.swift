import Combine
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// BLE 近场分享传输门面：UI 只依赖本类型，CoreBluetooth 细节在 `NearbyShareBLEAdapter`。
@MainActor
final class NearbyShareTransport: ObservableObject {
    struct Peer: Identifiable, Equatable {
        let id: String
        let displayName: String
        let lastSeen: Date
        let rssi: Int?
        let connectionState: NearbyShareConnectionState
    }

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isReceiving = false
    @Published private(set) var authorizationState: NearbyShareAuthorizationState = .unknown
    @Published private(set) var sendState: NearbyShareSendState?
    @Published private(set) var receiveState: NearbyShareReceiveState = .idle

    var onTicketReceived: ((String) -> Void)?

    private let adapter = NearbyShareBLEAdapter()

    init() {
        adapter.delegate = self
    }

    func configureShare(outbound: NearbyShareOutboundPayload) {
        adapter.configureShare(outbound: outbound)
    }

    func startDiscovery() {
        isScanning = true
        sendState = nil
        adapter.startScanning()
    }

    func stopDiscovery() {
        isScanning = false
        adapter.stopScanning()
    }

    func startReceiving() {
        isReceiving = true
        receiveState = .advertising
        adapter.startReceiving(displayName: Self.defaultDisplayName())
    }

    func stopReceiving() {
        isReceiving = false
        adapter.stopReceiving()
        receiveState = .idle
    }

    func teardown() {
        stopDiscovery()
        stopReceiving()
        adapter.teardown()
    }

    func send(to peer: Peer) async throws {
        try await adapter.send(toSessionID: peer.id)
    }

    private static func defaultDisplayName() -> String {
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceName.isEmpty == false {
            return deviceName
        }
        #endif
        return L10n.text("home.members.share.nearby.anonymous_peer")
    }
}

extension NearbyShareTransport: NearbyShareBLEAdapterDelegate {
    nonisolated func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateAuthorization state: NearbyShareAuthorizationState) {
        Task { @MainActor in
            authorizationState = state
        }
    }

    nonisolated func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdatePeers snapshots: [NearbySharePeerSnapshot]) {
        Task { @MainActor in
            peers = snapshots.map {
                Peer(
                    id: $0.id,
                    displayName: $0.displayName,
                    lastSeen: $0.lastSeen,
                    rssi: $0.rssi,
                    connectionState: $0.connectionState
                )
            }
        }
    }

    nonisolated func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateSendState state: NearbyShareSendState?) {
        Task { @MainActor in
            sendState = state
        }
    }

    nonisolated func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateReceiveState state: NearbyShareReceiveState) {
        Task { @MainActor in
            receiveState = state
        }
    }

    nonisolated func bleAdapter(_ adapter: NearbyShareBLEAdapter, didReceiveInbound payload: NearbyShareInboundPayload) {
        Task { @MainActor in
            onTicketReceived?(payload.ticket)
        }
    }
}
