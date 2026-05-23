import CoreBluetooth
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct NearbySharePeerSnapshot: Equatable {
    let id: String
    let displayName: String
    let lastSeen: Date
    let rssi: Int?
    let connectionState: NearbyShareConnectionState
}

protocol NearbyShareBLEAdapterDelegate: AnyObject {
    func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateAuthorization state: NearbyShareAuthorizationState)
    func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdatePeers peers: [NearbySharePeerSnapshot])
    func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateSendState state: NearbyShareSendState?)
    func bleAdapter(_ adapter: NearbyShareBLEAdapter, didUpdateReceiveState state: NearbyShareReceiveState)
    func bleAdapter(_ adapter: NearbyShareBLEAdapter, didReceiveInbound payload: NearbyShareInboundPayload)
}

enum NearbyShareBLEError: LocalizedError {
    case bluetoothUnavailable
    case peerNotReady
    case writeFailed
    case payloadEncodingFailed

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return L10n.text("home.members.share.nearby.bluetooth_unavailable")
        case .peerNotReady:
            return L10n.text("home.members.share.nearby.send_failed")
        case .writeFailed:
            return L10n.text("home.members.share.nearby.send_failed")
        case .payloadEncodingFailed:
            return L10n.text("home.members.share.nearby.payload_too_large")
        }
    }
}

final class NearbyShareBLEAdapter: NSObject, @unchecked Sendable {
    weak var delegate: NearbyShareBLEAdapterDelegate?

    private let queue = DispatchQueue(label: "com.spark.nearby.ble")
    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var isScanning = false
    private var isReceiving = false
    private var outboundPayload: NearbyShareOutboundPayload?
    private var receiveSessionID: String?
    private var receiveDisplayName = ""
    private var beaconData: Data?
    private var payloadCharacteristic: CBMutableCharacteristic?
    private var pruneTimer: DispatchSourceTimer?
    private var isAppActive = true
    private var lifecycleObservers: [NSObjectProtocol] = []

    private var links: [UUID: PeripheralLink] = [:]
    private var sessionLinks: [String: UUID] = [:]
    private var pendingSend: (sessionID: String, continuation: CheckedContinuation<Void, Error>)?

    private struct PeripheralLink {
        let peripheral: CBPeripheral
        var beacon: NearbyShareBeacon?
        var payloadCharacteristic: CBCharacteristic?
        var rssi: Int
        var lastSeen: Date
        var connectionState: NearbyShareConnectionState
    }

    override init() {
        super.init()
        registerLifecycleObservers()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func configureShare(outbound: NearbyShareOutboundPayload) {
        queue.async { [weak self] in
            self?.outboundPayload = outbound
        }
    }

    func startScanning() {
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureManagers()
            self.isScanning = true
            self.startPruneTimerIfNeeded()
            self.scanIfPossible()
        }
    }

    func stopScanning() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isScanning = false
            if let central = self.central, central.state == .poweredOn {
                central.stopScan()
            }
            self.disconnectAllCentrals()
            self.publishPeers()
            self.stopPruneTimerIfIdle()
        }
    }

    func startReceiving(displayName: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureManagers()
            self.isReceiving = true
            self.receiveDisplayName = displayName
            self.receiveSessionID = Self.makeSessionID()
            let beacon = NearbyShareBeacon(
                v: 1,
                mode: NearbyShareBLE.receiveMode,
                sessionId: self.receiveSessionID ?? Self.makeSessionID(),
                displayName: displayName
            )
            self.beaconData = try? NearbySharePayloadCodec.encodeBeacon(beacon)
            self.publishReceiveState(.advertising)
            self.startPeripheralIfPossible()
        }
    }

    func stopReceiving() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isReceiving = false
            self.peripheralManager?.stopAdvertising()
            self.publishReceiveState(.idle)
            self.stopPruneTimerIfIdle()
        }
    }

    func teardown() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isScanning = false
            self.isReceiving = false
            self.central?.stopScan()
            self.peripheralManager?.stopAdvertising()
            self.disconnectAllCentrals()
            self.pruneTimer?.cancel()
            self.pruneTimer = nil
            self.publishPeers()
            self.publishReceiveState(.idle)
        }
    }

    func send(toSessionID sessionID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NearbyShareBLEError.peerNotReady)
                    return
                }
                guard let outbound = self.outboundPayload else {
                    continuation.resume(throwing: NearbyShareBLEError.payloadEncodingFailed)
                    return
                }
                guard let peripheralID = self.sessionLinks[sessionID],
                      let link = self.links[peripheralID],
                      let characteristic = link.payloadCharacteristic,
                      link.connectionState == .connected
                else {
                    continuation.resume(throwing: NearbyShareBLEError.peerNotReady)
                    return
                }
                let data: Data
                do {
                    data = try NearbySharePayloadCodec.encodeOutbound(outbound)
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                self.pendingSend = (sessionID, continuation)
                self.publishSendState(.sending)
                link.peripheral.writeValue(data, for: characteristic, type: .withResponse)
                self.links[peripheralID] = link
            }
        }
    }

    private func ensureManagers() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue)
        }
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
        }
    }

    private func scanIfPossible() {
        guard isScanning, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [NearbyShareBLE.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: isAppActive]
        )
    }

    private func registerLifecycleObservers() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.handleEnterBackground() }
            }
        )
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.handleEnterForeground() }
            }
        )
        #endif
    }

    private func handleEnterBackground() {
        isAppActive = false
        central?.stopScan()
        peripheralManager?.stopAdvertising()
    }

    private func handleEnterForeground() {
        isAppActive = true
        if isScanning { scanIfPossible() }
        if isReceiving { startPeripheralIfPossible() }
    }

    private func startPeripheralIfPossible() {
        guard isReceiving, let peripheralManager, peripheralManager.state == .poweredOn else { return }
        setupGATTServiceIfNeeded()
        guard peripheralManager.isAdvertising == false else { return }
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [NearbyShareBLE.serviceUUID]
        ])
    }

    private func setupGATTServiceIfNeeded() {
        guard let peripheralManager, payloadCharacteristic == nil else { return }
        let beaconCharacteristic = CBMutableCharacteristic(
            type: NearbyShareBLE.beaconCharacteristicUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        let writablePayload = CBMutableCharacteristic(
            type: NearbyShareBLE.payloadCharacteristicUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        payloadCharacteristic = writablePayload
        let service = CBMutableService(type: NearbyShareBLE.serviceUUID, primary: true)
        service.characteristics = [beaconCharacteristic, writablePayload]
        peripheralManager.add(service)
    }

    private func disconnectAllCentrals() {
        guard let central else { return }
        for link in links.values {
            if link.peripheral.state != .disconnected {
                central.cancelPeripheralConnection(link.peripheral)
            }
        }
        links.removeAll()
        sessionLinks.removeAll()
    }

    private func startPruneTimerIfNeeded() {
        guard pruneTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + NearbyShareBLE.peerPruneInterval, repeating: NearbyShareBLE.peerPruneInterval)
        timer.setEventHandler { [weak self] in
            self?.pruneStalePeers()
        }
        timer.resume()
        pruneTimer = timer
    }

    private func stopPruneTimerIfIdle() {
        guard isScanning == false, isReceiving == false else { return }
        pruneTimer?.cancel()
        pruneTimer = nil
    }

    private func pruneStalePeers() {
        let cutoff = Date().addingTimeInterval(-NearbyShareBLE.peerStaleInterval)
        let before = links.count
        links = links.filter { _, link in
            guard link.lastSeen >= cutoff else { return false }
            guard link.beacon?.mode == NearbyShareBLE.receiveMode else { return false }
            return true
        }
        sessionLinks = sessionLinks.filter { sessionID, peripheralID in
            links[peripheralID] != nil && links[peripheralID]?.beacon?.sessionId == sessionID
        }
        if links.count != before {
            publishPeers()
        }
    }

    private func publishPeers() {
        let snapshots: [NearbySharePeerSnapshot] = links.values.compactMap { link in
            guard let beacon = link.beacon, beacon.mode == NearbyShareBLE.receiveMode else { return nil }
            return NearbySharePeerSnapshot(
                id: beacon.sessionId,
                displayName: beacon.displayName,
                lastSeen: link.lastSeen,
                rssi: link.rssi,
                connectionState: link.connectionState
            )
        }
        .sorted { lhs, rhs in
            if lhs.lastSeen != rhs.lastSeen { return lhs.lastSeen > rhs.lastSeen }
            return (lhs.rssi ?? -100) > (rhs.rssi ?? -100)
        }
        .prefix(NearbyShareBLE.maxVisiblePeers)
        .map { $0 }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleAdapter(self, didUpdatePeers: snapshots)
        }
    }

    private func publishAuthorization(_ state: NearbyShareAuthorizationState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleAdapter(self, didUpdateAuthorization: state)
        }
    }

    private func publishSendState(_ state: NearbyShareSendState?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleAdapter(self, didUpdateSendState: state)
        }
    }

    private func publishReceiveState(_ state: NearbyShareReceiveState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleAdapter(self, didUpdateReceiveState: state)
        }
    }

    private func publishInbound(_ payload: NearbyShareInboundPayload) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleAdapter(self, didReceiveInbound: payload)
        }
    }

    private func authorizationState(for manager: CBManager) -> NearbyShareAuthorizationState {
        switch manager.state {
        case .poweredOn:
            return .ready
        case .unauthorized:
            return .unauthorized
        case .poweredOff, .unsupported, .resetting:
            return .poweredOff
        default:
            return .unknown
        }
    }

    private func handleManagerPoweredOn() {
        publishAuthorization(.ready)
        if isScanning { scanIfPossible() }
        if isReceiving { startPeripheralIfPossible() }
    }

    private static func makeSessionID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }
}

extension NearbyShareBLEAdapter: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishAuthorization(authorizationState(for: central))
        switch central.state {
        case .poweredOn:
            handleManagerPoweredOn()
        case .unauthorized:
            publishAuthorization(.unauthorized)
        case .poweredOff, .unsupported:
            publishAuthorization(.poweredOff)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isScanning else { return }
        let id = peripheral.identifier
        var link = links[id] ?? PeripheralLink(
            peripheral: peripheral,
            beacon: nil,
            payloadCharacteristic: nil,
            rssi: RSSI.intValue,
            lastSeen: Date(),
            connectionState: .discovered
        )
        link.rssi = RSSI.intValue
        link.lastSeen = Date()
        links[id] = link
        peripheral.delegate = self
        if peripheral.state == .disconnected {
            link.connectionState = .connecting
            links[id] = link
            central.connect(peripheral, options: nil)
        }
        publishPeers()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        guard var link = links[id] else { return }
        link.connectionState = .connected
        links[id] = link
        peripheral.discoverServices([NearbyShareBLE.serviceUUID])
        publishPeers()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        guard var link = links[id] else { return }
        link.connectionState = .failed
        links[id] = link
        publishPeers()
        if let pending = pendingSend, sessionLinks[pending.sessionID] == id {
            pending.continuation.resume(throwing: NearbyShareBLEError.writeFailed)
            pendingSend = nil
            publishSendState(.failed(L10n.text("home.members.share.nearby.send_failed")))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        links.removeValue(forKey: peripheral.identifier)
        sessionLinks = sessionLinks.filter { $0.value != peripheral.identifier }
        publishPeers()
    }
}

extension NearbyShareBLEAdapter: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == NearbyShareBLE.serviceUUID }) else { return }
        peripheral.discoverCharacteristics(
            [NearbyShareBLE.beaconCharacteristicUUID, NearbyShareBLE.payloadCharacteristicUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        let id = peripheral.identifier
        guard var link = links[id] else { return }
        if let beaconChar = service.characteristics?.first(where: { $0.uuid == NearbyShareBLE.beaconCharacteristicUUID }) {
            peripheral.readValue(for: beaconChar)
        }
        link.payloadCharacteristic = service.characteristics?.first(where: { $0.uuid == NearbyShareBLE.payloadCharacteristicUUID })
        links[id] = link
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == NearbyShareBLE.beaconCharacteristicUUID,
              let data = characteristic.value
        else { return }
        let id = peripheral.identifier
        guard var link = links[id] else { return }
        do {
            let beacon = try NearbySharePayloadCodec.decodeBeacon(data)
            guard beacon.mode == NearbyShareBLE.receiveMode else { return }
            link.beacon = beacon
            links[id] = link
            sessionLinks[beacon.sessionId] = id
            publishPeers()
        } catch {
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == NearbyShareBLE.payloadCharacteristicUUID else { return }
        guard let pending = pendingSend else { return }
        pendingSend = nil
        if let error {
            pending.continuation.resume(throwing: error)
            publishSendState(.failed(L10n.text("home.members.share.nearby.send_failed")))
            return
        }
        pending.continuation.resume()
        publishSendState(.sent)
    }
}

extension NearbyShareBLEAdapter: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        publishAuthorization(authorizationState(for: peripheral))
        if peripheral.state == .poweredOn {
            if isReceiving { startPeripheralIfPossible() }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            publishReceiveState(.failed(L10n.text("home.members.share.nearby.bluetooth_unavailable")))
            return
        }
        startPeripheralIfPossible()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            publishReceiveState(.failed(error.localizedDescription))
        } else {
            publishReceiveState(.advertising)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == NearbyShareBLE.payloadCharacteristicUUID {
            guard let data = request.value else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }
            do {
                let inbound = try NearbySharePayloadCodec.decodeInbound(data)
                if request.characteristic === payloadCharacteristic {
                    // respond success before UI
                }
                peripheral.respond(to: request, withResult: .success)
                publishReceiveState(.received)
                publishInbound(inbound)
            } catch {
                peripheral.respond(to: request, withResult: .unlikelyError)
                publishReceiveState(.failed(error.localizedDescription))
            }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == NearbyShareBLE.beaconCharacteristicUUID else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
            return
        }
        guard let data = beaconData else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        if request.offset > data.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }
}
