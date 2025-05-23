// StreetPass_BLEManager.swift
// Manages all Bluetooth LE communications for StreetPass Encounter Card exchange.
// Handles both Central (scanning, connecting) and Peripheral (advertising, responding) roles.

import Foundation
import CoreBluetooth
import Combine // For @Published properties

// MARK: - Delegate Protocol
protocol StreetPassBLEManagerDelegate: AnyObject {
    func bleManagerDidUpdateState(bluetoothState: CBManagerState)
    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?)
    func bleManagerDidUpdateLog(_ message: String)
    func bleManagerDidEncounterError(_ error: StreetPassBLEError)
}

// MARK: - Error Enum for BLE Operations
enum StreetPassBLEError: Error, LocalizedError {
    case bluetoothUnavailable(String)
    case dataSerializationError(String)
    case dataDeserializationError(String)
    case characteristicOperationFailed(String)
    case connectionFailed(String)
    case serviceSetupFailed(String)
    case advertisingFailed(String)
    case internalInconsistency(String)

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let msg): return "Bluetooth Issue: \(msg)"
        case .dataSerializationError(let msg): return "Data Encoding Error: \(msg)"
        case .dataDeserializationError(let msg): return "Data Decoding Error: \(msg)"
        case .characteristicOperationFailed(let msg): return "Bluetooth Characteristic Error: \(msg)"
        case .connectionFailed(let msg): return "Peer Connection Failed: \(msg)"
        case .serviceSetupFailed(let msg): return "Bluetooth Service Setup Failed: \(msg)"
        case .advertisingFailed(let msg): return "Bluetooth Advertising Failed: \(msg)"
        case .internalInconsistency(let msg): return "StreetPass System Error: \(msg)"
        }
    }
}

// MARK: - BLE Service and Characteristic UUIDs
struct StreetPassBLE_UUIDs {
    // CORRECTED: Use actual UUIDs generated by `uuidgen` or similar tool.
    static let streetPassServiceUUID_String = "DEADBEEF-1234-5678-9ABC-DEF012345678" // Replace with your generated UUID
    static let encounterCardCharacteristicUUID_String = "CAFEF00D-0000-1111-2222-333344445555" // Replace with your generated UUID

    // These initializations will now work correctly
    static let streetPassServiceUUID = CBUUID(string: streetPassServiceUUID_String)
    static let encounterCardCharacteristicUUID = CBUUID(string: encounterCardCharacteristicUUID_String)
}

// Add CBPeripheralDelegate to the main class declaration
class StreetPassBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {

    weak var delegate: StreetPassBLEManagerDelegate?

    @Published var isBluetoothPoweredOn: Bool = false
    @Published var isScanning: Bool = false
    @Published var isAdvertising: Bool = false
    @Published var localUserCard: EncounterCard
    @Published var receivedCards: [EncounterCard] = []
    @Published var activityLog: [String] = []

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    private var connectingOrConnectedPeer: CBPeripheral?
    private var peerRSSICache: [UUID: NSNumber] = [:]

    private var encounterCardMutableCharacteristic: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    private var lastEncounterTimeByUser: [String: Date] = [:]
    private let encounterDebounceInterval: TimeInterval = 60

    private let localUserCardStorageKey = "streetPass_LocalUserCard_v2"
    private let receivedCardsStorageKey = "streetPass_ReceivedCards_v2"

    init(userID: String) {
        self.localUserCard = EncounterCard(userID: userID)
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        log("StreetPass BLE Manager initialized for UserID: \(userID). Waiting for Bluetooth power state.")
        loadReceivedCardsFromPersistence()
    }

    func log(_ message: String, level: LogLevel = .info) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let prefix = level == .error ? "ERROR:" : (level == .warning ? "WARN:" : "INFO:")
            let fullMessage = "\(timestamp) \(prefix) \(message)"
            print("StreetPassBLE: \(fullMessage)")
            self.activityLog.insert(fullMessage, at: 0)
            if self.activityLog.count > 250 {
                self.activityLog.removeLast(self.activityLog.count - 250)
            }
            self.delegate?.bleManagerDidUpdateLog(fullMessage)
        }
    }
    enum LogLevel { case info, warning, error }

    public func start() {
        log("Request to start StreetPass services (Scanning & Advertising).")
        if centralManager.state == .poweredOn { startScanning() }
        if peripheralManager.state == .poweredOn { setupServiceAndStartAdvertising() }
    }

    public func stop() {
        log("Request to stop StreetPass services.")
        stopScanning()
        stopAdvertising()
        if let peer = connectingOrConnectedPeer {
            log("Cancelling active connection to peer: \(String(peer.identifier.uuidString.prefix(8)))", level: .info)
            centralManager.cancelPeripheralConnection(peer)
            connectingOrConnectedPeer = nil
        }
    }

    public func updateLocalUserCard(newCard: EncounterCard) {
        guard newCard.userID == self.localUserCard.userID else {
            log("Critical error: Attempt to update card with mismatched UserID. Current: \(self.localUserCard.userID), New: \(newCard.userID)", level: .error)
            delegate?.bleManagerDidEncounterError(.internalInconsistency("UserID mismatch during card update."))
            return
        }
        let contentActuallyChanged = self.localUserCard.isContentDifferent(from: newCard)
        self.localUserCard = newCard
        if contentActuallyChanged { self.localUserCard.id = UUID() }
        self.localUserCard.lastUpdated = Date()
        log("Local user card updated. DisplayName: '\(newCard.displayName)'. Content changed: \(contentActuallyChanged).")
        saveLocalUserCardToPersistence()
        if isAdvertising, let characteristic = self.encounterCardMutableCharacteristic {
            do {
                let cardData = try jsonEncoder.encode(self.localUserCard)
                characteristic.value = cardData
                if !subscribedCentrals.isEmpty {
                    log("Notifying \(subscribedCentrals.count) subscribed central(s) of local card update...")
                    let success = peripheralManager.updateValue(cardData, for: characteristic, onSubscribedCentrals: nil)
                    log(success ? "Notification queued successfully." : "Failed to queue notification (buffer full).", level: success ? .info : .warning)
                }
            } catch {
                let errorMsg = "Encoding local card for characteristic update/notification failed: \(error.localizedDescription)"
                log(errorMsg, level: .error)
                delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg))
            }
        }
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Central: Bluetooth not powered on. Scan deferred.", level: .warning); return
        }
        if isScanning { log("Central: Already scanning."); return }
        log("Central: Starting scan for StreetPass service: \(StreetPassBLE_UUIDs.streetPassServiceUUID.uuidString)")
        centralManager.scanForPeripherals(withServices: [StreetPassBLE_UUIDs.streetPassServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.async { self.isScanning = true }
    }

    private func stopScanning() {
        if centralManager.isScanning { centralManager.stopScan(); log("Central: Scanning stopped.") }
        DispatchQueue.main.async { self.isScanning = false }
    }

    private func setupServiceAndStartAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            log("Peripheral: Bluetooth not powered on. Service setup deferred.", level: .warning); return
        }
        if isAdvertising && encounterCardMutableCharacteristic != nil { log("Peripheral: Already advertising with service configured."); return }
        log("Peripheral: Setting up Encounter Card service...")
        self.encounterCardMutableCharacteristic = CBMutableCharacteristic(type: StreetPassBLE_UUIDs.encounterCardCharacteristicUUID, properties: [.read, .write, .notify], value: nil, permissions: [.readable, .writeable])
        let service = CBMutableService(type: StreetPassBLE_UUIDs.streetPassServiceUUID, primary: true)
        service.characteristics = [self.encounterCardMutableCharacteristic!]
        peripheralManager.removeAllServices()
        log("Peripheral: Adding service \(service.uuid.uuidString)...")
        peripheralManager.add(service)
    }
    
    private func actuallyStartAdvertising() {
        if isAdvertising { log("Peripheral: Already advertising.", level: .info); return }
        let advData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [StreetPassBLE_UUIDs.streetPassServiceUUID]]
        log("Peripheral: Starting advertising with data: \(advData)")
        peripheralManager.startAdvertising(advData)
    }

    private func stopAdvertising() {
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising(); log("Peripheral: Advertising stopped.") }
        DispatchQueue.main.async { self.isAdvertising = false }
    }
    
    private func processAndStoreReceivedCard(_ card: EncounterCard, rssi: NSNumber?) {
        let now = Date()
        if let lastTime = lastEncounterTimeByUser[card.userID], now.timeIntervalSince(lastTime) < encounterDebounceInterval {
            log("Debounced: Card from UserID '\(card.userID)' received again too soon. Ignoring. Last: \(formatTimestampForLog(lastTime)), Now: \(formatTimestampForLog(now))")
            return
        }
        DispatchQueue.main.async {
            var isUpdate = false
            if let index = self.receivedCards.firstIndex(where: { $0.userID == card.userID }) {
                if card.lastUpdated > self.receivedCards[index].lastUpdated || card.cardSchemaVersion > self.receivedCards[index].cardSchemaVersion {
                    self.receivedCards[index] = card; isUpdate = true
                    self.log("Updated card for UserID: '\(card.userID)' (Name: \(card.displayName)).")
                } else { self.log("Received card for UserID: '\(card.userID)' is not newer. No update made."); return }
            } else { self.receivedCards.append(card); self.log("Added new card from UserID: '\(card.userID)' (Name: \(card.displayName)).") }
            self.receivedCards.sort(by: { $0.lastUpdated > $1.lastUpdated })
            self.saveReceivedCardsToPersistence()
            self.lastEncounterTimeByUser[card.userID] = now
            self.delegate?.bleManagerDidReceiveCard(card, rssi: rssi)
        }
    }
    private func formatTimestampForLog(_ date: Date) -> String { let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return formatter.string(from: date) }

    func loadLocalUserCardFromPersistence() {
        log("Loading local user card from persistence...")
        if let data = UserDefaults.standard.data(forKey: localUserCardStorageKey) {
            do {
                let loadedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
                if loadedCard.userID == self.localUserCard.userID { self.localUserCard = loadedCard; log("Successfully loaded local user card: '\(loadedCard.displayName)'") }
                else { log("Persisted card has different UserID (\(loadedCard.userID)) than current (\(self.localUserCard.userID)). Resetting to default for current user.", level: .warning); saveLocalUserCardToPersistence() }
            } catch {
                let errorMsg = "Decoding local user card failed: \(error.localizedDescription). Using default."
                log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg)); saveLocalUserCardToPersistence()
            }
        } else { log("No local user card found in persistence. Saving current default."); saveLocalUserCardToPersistence() }
        objectWillChange.send()
    }

    private func saveLocalUserCardToPersistence() {
        do { try UserDefaults.standard.set(jsonEncoder.encode(localUserCard), forKey: localUserCardStorageKey); log("Saved local user card ('\(localUserCard.displayName)') to UserDefaults.") }
        catch { let errorMsg = "Encoding local user card for persistence failed: \(error.localizedDescription)"; log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
    }

    private func loadReceivedCardsFromPersistence() {
        log("Loading received cards from persistence...")
        if let data = UserDefaults.standard.data(forKey: receivedCardsStorageKey) {
            do { self.receivedCards = try jsonDecoder.decode([EncounterCard].self, from: data).sorted(by: { $0.lastUpdated > $1.lastUpdated }); log("Loaded \(self.receivedCards.count) received cards.") }
            catch { let errorMsg = "Decoding received cards failed: \(error.localizedDescription). Clearing local cache."; log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg)); self.receivedCards = [] }
        } else { log("No received cards found in persistence."); self.receivedCards = [] }
        objectWillChange.send()
    }

    private func saveReceivedCardsToPersistence() {
        do { try UserDefaults.standard.set(jsonEncoder.encode(receivedCards), forKey: receivedCardsStorageKey); log("Saved \(receivedCards.count) received cards to UserDefaults.") }
        catch { let errorMsg = "Encoding received cards for persistence failed: \(error.localizedDescription)"; log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
    }
    
    public func clearReceivedCardsFromPersistence() {
        DispatchQueue.main.async {
            self.receivedCards.removeAll(); self.lastEncounterTimeByUser.removeAll()
            UserDefaults.standard.removeObject(forKey: self.receivedCardsStorageKey)
            self.log("All received cards and debounce history cleared from persistence.", level: .info)
            self.objectWillChange.send()
        }
    }
    
    private func attemptCardTransmissionToPeer(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else {
            log("Central: Peer's CardData characteristic does not support write. Cannot send our card.", level: .warning); return
        }
        log("Central: Preparing to send our card to Peer: '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'.")
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            log("Central: Writing our card (\(cardData.count) bytes) via \(writeType == .withResponse ? "Response" : "NoResponse").")
            peripheral.writeValue(cardData, for: characteristic, type: writeType)
        } catch {
            let errorMsg = "Encoding local card for transmission failed: \(error.localizedDescription)"
            log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg))
        }
    }

    // MARK: - CBCentralManagerDelegate Methods (Implemented in main class body due to combined delegate conformance)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.isBluetoothPoweredOn = (central.state == .poweredOn && self.peripheralManager.state == .poweredOn) }
        delegate?.bleManagerDidUpdateState(bluetoothState: central.state)
        switch central.state {
        case .poweredOn: log("Central Manager: Bluetooth Powered ON."); startScanning()
        case .poweredOff: log("Central Manager: Bluetooth Powered OFF.", level: .warning); DispatchQueue.main.async { self.isScanning = false }; delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("Bluetooth is Off"))
        default: log("Central Manager: State changed to \(central.state.rawValue)", level: .info)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        // CORRECTED: Convert Substring to String for suffix/prefix
        log("Central: Discovered '\(name)' (RSSI: \(RSSI)). ID: ...\(String(peripheral.identifier.uuidString.suffix(6)))")
        peerRSSICache[peripheral.identifier] = RSSI

        if connectingOrConnectedPeer != nil {
            log("Central: Busy with another peer (\(connectingOrConnectedPeer!.name ?? "ID")). Ignoring discovery of '\(name)'.", level: .info)
            return
        }
        log("Central: Attempting connection to '\(name)' for card exchange...")
        connectingOrConnectedPeer = peripheral
        centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // CORRECTED: Convert Substring to String for prefix
        log("Central: Connected to '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Discovering StreetPass service...")
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central: Connected to an unexpected peripheral. Disconnecting.", level: .warning)
            central.cancelPeripheralConnection(peripheral)
            if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil }
            return
        }
        peripheral.delegate = self // This line needs StreetPassBLEManager to conform to CBPeripheralDelegate
        peripheral.discoverServices([StreetPassBLE_UUIDs.streetPassServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // CORRECTED: Convert Substring to String for prefix
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8))
        let errStr = error?.localizedDescription ?? "unknown reason"
        log("Central: Failed to connect to '\(name)'. Error: \(errStr)", level: .error)
        if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil }
        delegate?.bleManagerDidEncounterError(.connectionFailed("Connect to '\(name)' failed: \(errStr)"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // CORRECTED: Convert Substring to String for prefix
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8))
        if let err = error {
            log("Central: Disconnected from '\(name)' with error: \(err.localizedDescription)", level: .warning)
            delegate?.bleManagerDidEncounterError(.connectionFailed("Disconnected from '\(name)': \(err.localizedDescription)"))
        } else {
            log("Central: Disconnected cleanly from '\(name)'.")
        }
        if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil }
        peerRSSICache.removeValue(forKey: peripheral.identifier)
    }

    // MARK: - CBPeripheralDelegate Methods (for Central role's interaction with connected Peripheral)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else { return }
        if let err = error {
            log("Central/PeerDelegate: Error discovering services on '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Service discovery on peer failed: \(err.localizedDescription)"))
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == StreetPassBLE_UUIDs.streetPassServiceUUID }) else {
            log("Central/PeerDelegate: StreetPass service not found on '\(peripheral.name ?? "")'. Disconnecting.", level: .warning)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.serviceSetupFailed("StreetPass service not found on peer."))
            return
        }
        log("Central/PeerDelegate: Found StreetPass service on '\(peripheral.name ?? "")'. Discovering EncounterCard characteristic...")
        peripheral.discoverCharacteristics([StreetPassBLE_UUIDs.encounterCardCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else { return }
        if service.uuid != StreetPassBLE_UUIDs.streetPassServiceUUID { return }
        if let err = error {
            log("Central/PeerDelegate: Error discovering characteristics for service \(service.uuid) on '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Characteristic discovery failed: \(err.localizedDescription)"))
            return
        }
        guard let cardChar = service.characteristics?.first(where: { $0.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID }) else {
            log("Central/PeerDelegate: EncounterCard characteristic not found in service. Disconnecting.", level: .warning)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("EncounterCard characteristic not found."))
            return
        }
        log("Central/PeerDelegate: Found EncounterCard characteristic. Properties: \(cardChar.properties)")
        if cardChar.properties.contains(.notify) {
            log("Central/PeerDelegate: Subscribing to notifications for peer's card...")
            peripheral.setNotifyValue(true, for: cardChar)
        } else if cardChar.properties.contains(.read) {
            log("Central/PeerDelegate: Characteristic not notifiable. Attempting direct read for peer's card...", level: .warning)
            peripheral.readValue(for: cardChar)
        } else {
            log("Central/PeerDelegate: Characteristic neither notifiable nor readable. Cannot exchange. Disconnecting.", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Peer's card characteristic unusable."))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        if let err = error {
            log("Central/PeerDelegate: Error subscribing to CardData: \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Subscription to peer's card failed: \(err.localizedDescription)"))
            return
        }
        if characteristic.isNotifying {
            log("Central/PeerDelegate: Subscribed successfully to peer's card notifications. Sending our card...")
            attemptCardTransmissionToPeer(peripheral: peripheral, characteristic: characteristic)
        } else { log("Central/PeerDelegate: Peer unsubscribed or notifications stopped.", level: .warning) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        if let err = error {
            log("Central/PeerDelegate: Error writing our card to peer: \(err.localizedDescription)", level: .error)
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Write of local card to peer failed: \(err.localizedDescription)"))
        } else { log("Central/PeerDelegate: Successfully wrote our card to peer.") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        if let err = error {
            log("Central/PeerDelegate: Error receiving card data value from peer: \(err.localizedDescription)", level: .error)
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Receiving peer's card data failed: \(err.localizedDescription)"))
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil; return
        }
        guard let data = characteristic.value else { log("Central/PeerDelegate: Received nil data for CardData. Ignoring.", level: .warning); return }
        log("Central/PeerDelegate: Received data (\(data.count) bytes) from peer. Decoding card...")
        do {
            let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
            log("Central/PeerDelegate: Decoded card from '\(receivedCard.displayName)'.")
            let rssi = peerRSSICache[peripheral.identifier]
            processAndStoreReceivedCard(receivedCard, rssi: rssi)
            log("Central/PeerDelegate: Card exchange complete with '\(peripheral.name ?? "")'. Disconnecting.")
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            peerRSSICache.removeValue(forKey: peripheral.identifier)
        } catch {
            let errorMsg = "Decoding peer's card failed: \(error.localizedDescription). Data snippet: \(String(data: data.prefix(50), encoding: .utf8) ?? "Non-UTF8")"
            log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg))
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else { return }
        if let err = error { log("Central/PeerDelegate: Error reading RSSI: \(err.localizedDescription)", level: .warning); return }
        log("Central/PeerDelegate: Updated RSSI for '\(peripheral.name ?? "")': \(RSSI)")
        peerRSSICache[peripheral.identifier] = RSSI
    }

    // MARK: - CBPeripheralManagerDelegate Methods (Implemented in main class body)
    func peripheralManagerDidUpdateState(_ peripheralManager: CBPeripheralManager) {
        DispatchQueue.main.async { self.isBluetoothPoweredOn = (peripheralManager.state == .poweredOn && self.centralManager.state == .poweredOn) }
        delegate?.bleManagerDidUpdateState(bluetoothState: peripheralManager.state)
        switch peripheralManager.state {
        case .poweredOn: log("Peripheral Manager: Bluetooth Powered ON."); setupServiceAndStartAdvertising()
        case .poweredOff: log("Peripheral Manager: Bluetooth Powered OFF.", level: .warning); DispatchQueue.main.async { self.isAdvertising = false }; delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("Peripheral Bluetooth is Off"))
        default: log("Peripheral Manager: State changed to \(peripheralManager.state.rawValue)", level: .info)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Error adding service \(service.uuid.uuidString): \(err.localizedDescription)", level: .error)
            delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Failed to add BLE service: \(err.localizedDescription)"))
            return
        }
        log("Peripheral/MgrDelegate: Service \(service.uuid.uuidString) added. Starting advertising...")
        actuallyStartAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Failed to start advertising: \(err.localizedDescription)", level: .error)
            DispatchQueue.main.async { self.isAdvertising = false }
            delegate?.bleManagerDidEncounterError(.advertisingFailed(err.localizedDescription))
            return
        }
        log("Peripheral/MgrDelegate: Successfully started advertising StreetPass service.")
        DispatchQueue.main.async { self.isAdvertising = true }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let centralIDPart = String(request.central.identifier.uuidString.prefix(8)) // Corrected: String conversion
        log("Peripheral/MgrDelegate: Read request for Char \(String(request.characteristic.uuid.uuidString.prefix(8))) from Central \(centralIDPart)...") // Corrected
        guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Peripheral/MgrDelegate: Read for unknown char. Responding 'AttributeNotFound'.", level: .warning) // Corrected error code
            manager.respond(to: request, withResult: .attributeNotFound); return
        }
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            request.value = cardData.subdataIfAppropriate(offset: request.offset, maxLength: request.central.maximumUpdateValueLength)
            if request.value == nil { manager.respond(to: request, withResult: .invalidOffset); return }
            manager.respond(to: request, withResult: .success)
            log("Peripheral/MgrDelegate: Responded to read from \(centralIDPart) with local card data (\(request.value?.count ?? 0) bytes).")
        } catch {
            log("Peripheral/MgrDelegate: Encoding local card for read failed: \(error.localizedDescription)", level: .error)
            manager.respond(to: request, withResult: .unlikelyError)
            delegate?.bleManagerDidEncounterError(.dataSerializationError("Encoding card for read failed: \(error.localizedDescription)"))
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let centralIDPart = String(request.central.identifier.uuidString.prefix(8)) // Corrected
            guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
                log("Peripheral/MgrDelegate: Write for unknown char from \(centralIDPart). Responding 'AttributeNotFound'.", level: .warning) // Corrected
                manager.respond(to: request, withResult: .attributeNotFound); continue
            }
            guard let data = request.value, !data.isEmpty else {
                log("Peripheral/MgrDelegate: Write with no data from \(centralIDPart). Responding 'InvalidAttributeValueLength'.", level: .warning)
                manager.respond(to: request, withResult: .invalidAttributeValueLength); continue
            }
            log("Peripheral/MgrDelegate: Received write (\(data.count) bytes) from Central \(centralIDPart). Decoding...")
            do {
                let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
                log("Peripheral/MgrDelegate: Decoded card from '\(receivedCard.displayName)' (Central \(centralIDPart)). Processing...")
                processAndStoreReceivedCard(receivedCard, rssi: nil)
                manager.respond(to: request, withResult: .success)
            } catch {
                log("Peripheral/MgrDelegate: Decoding card from Central \(centralIDPart) failed: \(error.localizedDescription)", level: .error)
                manager.respond(to: request, withResult: .unlikelyError) // Corrected error code
                delegate?.bleManagerDidEncounterError(.dataDeserializationError("Decoding peer's card write failed: \(error.localizedDescription)"))
            }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        let centralIDPart = String(central.identifier.uuidString.prefix(8)) // Corrected
        log("Peripheral/MgrDelegate: Central \(centralIDPart) subscribed to EncounterCard characteristic.")
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) { subscribedCentrals.append(central) }
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            if manager.updateValue(cardData, for: self.encounterCardMutableCharacteristic!, onSubscribedCentrals: [central]) {
                log("Peripheral/MgrDelegate: Sent initial card data notification to new subscriber \(centralIDPart).")
            } else { log("Peripheral/MgrDelegate: Failed to queue initial notification for \(centralIDPart) (buffer full). Will retry if manager becomes ready.", level: .warning) }
        } catch { log("Peripheral/MgrDelegate: Encoding card for initial notification failed: \(error.localizedDescription)", level: .error) }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        log("Peripheral/MgrDelegate: Central \(String(central.identifier.uuidString.prefix(8))) unsubscribed.") // Corrected
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        log("Peripheral/MgrDelegate: Ready to update subscribers again. (Implement retry for queued notifications).")
    }
}

extension Data {
    func subdataIfAppropriate(offset: Int, maxLength: Int) -> Data? {
        guard offset >= 0 else { log_ble_data_helper("Invalid offset: \(offset)"); return nil }
        if offset > self.count { log_ble_data_helper("Offset \(offset) beyond data count \(self.count). Returning nil as per stricter interpretation (CoreBluetooth might expect empty Data for read)."); return Data() } // Return empty data for offset past end for reads.
        if offset == self.count { return Data() } // If offset is exactly at the end, return empty data

        let startIndex = self.index(self.startIndex, offsetBy: offset)
        // Use Swift.min to disambiguate
        let currentLength = self.count - offset
        let lengthToTake = Swift.min(maxLength, currentLength) // Corrected
        
        let endIndex = self.index(startIndex, offsetBy: lengthToTake)
        // log_ble_data_helper("Subdata: Total \(self.count), Offset \(offset), MaxLength \(maxLength), Taking \(lengthToTake) bytes.")
        return self.subdata(in: startIndex..<endIndex)
    }
}
// Helper for Data extension logging if needed, to avoid direct app.logger calls from extension
func log_ble_data_helper(_ message: String) {
    // This is a bit of a hack. Ideally, extensions don't log directly or take a logger.
    // For now, just print.
    // print("StreetPassBLE/DataHelper: \(message)")
}
