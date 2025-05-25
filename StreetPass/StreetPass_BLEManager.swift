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
    static let streetPassServiceUUID_String = "DEADBEEF-1234-5678-9ABC-DEF012345678"
    static let encounterCardCharacteristicUUID_String = "CAFEF00D-0000-1111-2222-333344445555"

    static let streetPassServiceUUID = CBUUID(string: streetPassServiceUUID_String)
    static let encounterCardCharacteristicUUID = CBUUID(string: encounterCardCharacteristicUUID_String)

    static func allCharacteristicUUIDs() -> [CBUUID] {
        return [encounterCardCharacteristicUUID]
    }
}

fileprivate struct PeripheralCharacteristicPair: Hashable {
    let peripheralID: UUID
    let characteristicID: CBUUID
}

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

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder) -> Date in
            let container = try decoder.singleValueContainer()
            if let dateString = try? container.decode(String.self) {
                // Try specific ISO8601 formatters first
                let isoFormatters = [
                    ISO8601DateFormatter(), // Default ISO8601
                    { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                    { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
                ]
                for formatter in isoFormatters {
                    if let date = formatter.date(from: dateString) { return date }
                }

                // Try common DateFormatter patterns as fallback if ISO8601DateFormatter fails for some reason
                let commonFormatters = [
                    { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
                    { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
                ]
                for formatter in commonFormatters {
                    if let date = (formatter as AnyObject).date(from: dateString) { return date }
                }
            }
            if let timeInterval = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSinceReferenceDate: timeInterval)
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: not a recognized ISO8601 string or numeric timestamp.")
        }
        return decoder
    }()
    
    private var lastEncounterTimeByUser: [String: Date] = [:]
    private let encounterDebounceInterval: TimeInterval = 60

    private let localUserCardStorageKey = "streetPass_LocalUserCard_v2"
    private let receivedCardsStorageKey = "streetPass_ReceivedCards_v2"
    
    private var incomingDataBuffers: [PeripheralCharacteristicPair: Data] = [:]

    init(userID: String) {
        self.localUserCard = EncounterCard(userID: userID)
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        log("StreetPass BLE Manager initialized for UserID: \(userID). Waiting for Bluetooth power state.")
        loadLocalUserCardFromPersistence()
        loadReceivedCardsFromPersistence()
    }

    func log(_ message: String, level: LogLevel = .info) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let prefix: String
            switch level {
            case .error: prefix = "ERROR:"
            case .warning: prefix = "WARN:"
            case .info: prefix = "INFO:"
            }
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
        log("Request to start StreetPass services.")
        if let peer = connectingOrConnectedPeer {
            log("Start called, cancelling any existing connection to \(String(describing: peer.identifier.uuidString.prefix(8)))", level: .warning) // CORRECTED: String conversion
            centralManager.cancelPeripheralConnection(peer)
            connectingOrConnectedPeer = nil
        }
        if centralManager.state == .poweredOn { startScanning() }
        else { log("Central Manager not powered on. Scan deferred.", level: .warning) }
        if peripheralManager.state == .poweredOn { setupServiceAndStartAdvertising() }
        else { log("Peripheral Manager not powered on. Advertising deferred.", level: .warning) }
    }

    public func stop() {
        log("Request to stop StreetPass services.")
        stopScanning()
        stopAdvertising()
        if let peer = connectingOrConnectedPeer {
            log("Stop called, cancelling active connection to peer: \(String(describing: peer.identifier.uuidString.prefix(8)))") // CORRECTED: String conversion
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
        if contentActuallyChanged || self.localUserCard.id == EncounterCard(userID: self.localUserCard.userID).id {
            self.localUserCard.id = UUID()
        }
        self.localUserCard.lastUpdated = Date()
        log("Local user card updated. DisplayName: '\(self.localUserCard.displayName)'. NewID: \(self.localUserCard.id). Drawing size: \(self.localUserCard.drawingData?.count ?? 0) bytes. Content changed: \(contentActuallyChanged).")
        saveLocalUserCardToPersistence()
        if isAdvertising, let characteristic = self.encounterCardMutableCharacteristic {
            do {
                let cardData = try jsonEncoder.encode(self.localUserCard)
                characteristic.value = cardData
                log("Updated characteristic value in peripheral. Size: \(cardData.count) bytes.")
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
        objectWillChange.send()
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Central: Bluetooth not powered on. Scan deferred.", level: .warning); return
        }
        if isScanning { log("Central: Already scanning."); return }
        log("Central: Starting scan for StreetPass service: \(StreetPassBLE_UUIDs.streetPassServiceUUID.uuidString)")
        centralManager.scanForPeripherals(withServices: [StreetPassBLE_UUIDs.streetPassServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
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
        // CORRECTED: CBPeripheralManager does not have a 'services' property to check directly like CBPeripheral.
        // We check if our characteristic instance exists, implying service was set up.
        if encounterCardMutableCharacteristic != nil && peripheralManager.isAdvertising {
             log("Peripheral: Service likely configured and already advertising.")
             return
        }
        if encounterCardMutableCharacteristic != nil && !peripheralManager.isAdvertising {
             log("Peripheral: Service likely configured, but not advertising. Starting advertising...")
             actuallyStartAdvertising()
             return
        }

        log("Peripheral: Setting up Encounter Card service...")
        encounterCardMutableCharacteristic = CBMutableCharacteristic(
            type: StreetPassBLE_UUIDs.encounterCardCharacteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        let service = CBMutableService(type: StreetPassBLE_UUIDs.streetPassServiceUUID, primary: true)
        service.characteristics = [encounterCardMutableCharacteristic!]
        peripheralManager.removeAllServices()
        log("Peripheral: Adding service \(service.uuid.uuidString)...")
        peripheralManager.add(service)
    }
    
    private func actuallyStartAdvertising() {
        if isAdvertising { log("Peripheral: Already advertising or start attempt in progress.", level: .info); return }
        let advertisementData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [StreetPassBLE_UUIDs.streetPassServiceUUID]]
        log("Peripheral: Starting advertising with data: \(advertisementData)")
        peripheralManager.startAdvertising(advertisementData)
    }

    private func stopAdvertising() {
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising(); log("Peripheral: Advertising stopped.") }
        DispatchQueue.main.async { self.isAdvertising = false }
    }
    
    private func processAndStoreReceivedCard(_ card: EncounterCard, rssi: NSNumber?) {
        let now = Date()
        if let lastTime = lastEncounterTimeByUser[card.userID], now.timeIntervalSince(lastTime) < encounterDebounceInterval {
            log("Debounced: Card from UserID '\(card.userID)' (Name: \(card.displayName)) received again within \(encounterDebounceInterval)s. Last: \(formatTimestampForLog(lastTime)). Ignoring.", level: .info)
            return
        }
        DispatchQueue.main.async {
            var cardUpdatedInList = false
            if let index = self.receivedCards.firstIndex(where: { $0.userID == card.userID }) {
                if card.lastUpdated > self.receivedCards[index].lastUpdated || card.cardSchemaVersion > self.receivedCards[index].cardSchemaVersion {
                    self.receivedCards[index] = card
                    cardUpdatedInList = true
                    self.log("Updated card for UserID: '\(card.userID)' (Name: \(card.displayName)). Drawing: \(card.drawingData != nil).")
                } else {
                    self.log("Received card for UserID: '\(card.userID)' (Name: \(card.displayName)) is not newer. No UI update made. Drawing: \(card.drawingData != nil).")
                    self.lastEncounterTimeByUser[card.userID] = now
                    return
                }
            } else {
                self.receivedCards.append(card)
                cardUpdatedInList = true
                self.log("Added new card from UserID: '\(card.userID)' (Name: \(card.displayName)). Drawing: \(card.drawingData != nil).")
            }
            if cardUpdatedInList {
                self.receivedCards.sort(by: { $0.lastUpdated > $1.lastUpdated })
                self.saveReceivedCardsToPersistence()
                self.lastEncounterTimeByUser[card.userID] = now
                self.delegate?.bleManagerDidReceiveCard(card, rssi: rssi)
            }
        }
    }

    private func formatTimestampForLog(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss.SSS"; return formatter.string(from: date)
    }

    func loadLocalUserCardFromPersistence() {
        log("Loading local user card from persistence...")
        guard let data = UserDefaults.standard.data(forKey: localUserCardStorageKey) else {
            log("No local user card found in persistence. Saving current default/newly initialized card.")
            saveLocalUserCardToPersistence(); return
        }
        do {
            var loadedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
            if loadedCard.userID == self.localUserCard.userID {
                if loadedCard.cardSchemaVersion < EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion {
                    log("Loaded card schema (\(loadedCard.cardSchemaVersion)) is older. Updating to current schema (\(EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion)).", level: .warning)
                    loadedCard.cardSchemaVersion = EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion
                }
                self.localUserCard = loadedCard
                log("Successfully loaded local user card: '\(self.localUserCard.displayName)'. Schema: v\(self.localUserCard.cardSchemaVersion). Drawing: \(self.localUserCard.drawingData != nil)")
            } else {
                log("Persisted card UserID (\(loadedCard.userID)) MISMATCHES current (\(self.localUserCard.userID)). Resetting.", level: .error)
                self.localUserCard = EncounterCard(userID: self.localUserCard.userID)
                saveLocalUserCardToPersistence()
            }
        } catch {
            let errorMsg = "Decoding local user card failed: \(error.localizedDescription). Using default and resaving."
            log(errorMsg, level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg))
            self.localUserCard = EncounterCard(userID: self.localUserCard.userID)
            saveLocalUserCardToPersistence()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    private func saveLocalUserCardToPersistence() {
        do {
            let cardData = try jsonEncoder.encode(localUserCard)
            UserDefaults.standard.set(cardData, forKey: localUserCardStorageKey)
            log("Saved local user card ('\(localUserCard.displayName)', ID: \(String(localUserCard.id.uuidString.prefix(8)))) to UserDefaults. Size: \(cardData.count) bytes.")
        } catch {
            let errorMsg = "Encoding local user card for persistence failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg))
        }
    }

    private func loadReceivedCardsFromPersistence() {
        log("Loading received cards from persistence...")
        guard let data = UserDefaults.standard.data(forKey: receivedCardsStorageKey) else {
            log("No received cards found in persistence."); self.receivedCards = []; return
        }
        do {
            let loadedCards = try jsonDecoder.decode([EncounterCard].self, from: data)
            self.receivedCards = loadedCards.sorted(by: { $0.lastUpdated > $1.lastUpdated })
            log("Loaded \(self.receivedCards.count) received cards from persistence.")
            for card in self.receivedCards { self.lastEncounterTimeByUser[card.userID] = card.lastUpdated }
        } catch {
            let errorMsg = "Decoding received cards failed: \(error.localizedDescription). Clearing cache."; log(errorMsg, level: .error)
            delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg)); self.receivedCards = []
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    private func saveReceivedCardsToPersistence() {
        let maxReceivedCardsToSave = 50
        let cardsToSave = Array(receivedCards.prefix(maxReceivedCardsToSave))
        do {
            let receivedData = try jsonEncoder.encode(cardsToSave)
            UserDefaults.standard.set(receivedData, forKey: receivedCardsStorageKey)
            log("Saved \(cardsToSave.count) received cards to UserDefaults. Size: \(receivedData.count) bytes.")
        } catch {
            let errorMsg = "Encoding received cards failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg))
        }
    }
    
    public func clearReceivedCardsFromPersistence() {
        DispatchQueue.main.async {
            self.receivedCards.removeAll(); self.lastEncounterTimeByUser.removeAll()
            UserDefaults.standard.removeObject(forKey: self.receivedCardsStorageKey)
            self.log("All received cards and debounce history cleared.", level: .info)
            self.objectWillChange.send()
        }
    }
    
    private func attemptCardTransmissionToPeer(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else {
            log("Central: Peer's CardData char (\(String(characteristic.uuid.uuidString.prefix(8)))) no-write. No send.", level: .warning); return // CORRECTED
        }
        log("Central: Prep send our card to Peer: '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'.") // CORRECTED
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            log("Central: Writing our card (\(cardData.count) bytes) to \(String(characteristic.uuid.uuidString.prefix(8))) type \(writeType == .withResponse ? "Resp" : "NoResp").") // CORRECTED
            peripheral.writeValue(cardData, for: characteristic, type: writeType)
        } catch {
            let errorMsg = "Encoding local card for transmission failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg))
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.isBluetoothPoweredOn = (central.state == .poweredOn) }
        delegate?.bleManagerDidUpdateState(bluetoothState: central.state)
        switch central.state {
        case .poweredOn: log("Central Manager: Bluetooth ON."); startScanning()
        case .poweredOff: log("Central Manager: Bluetooth OFF.", level: .warning); DispatchQueue.main.async { self.isScanning = false }; delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT Off (Central)"))
            if let peer = connectingOrConnectedPeer { log("Central: BT off, cancel connect to \(String(peer.identifier.uuidString.prefix(8)))", level: .warning); centralManager.cancelPeripheralConnection(peer); connectingOrConnectedPeer = nil } // CORRECTED
        case .unauthorized: log("Central Manager: BT unauthorized.", level: .error); delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT permissions not granted."))
        case .unsupported: log("Central Manager: BT unsupported.", level: .error); delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT LE not supported."))
        case .resetting: log("Central Manager: BT resetting.", level: .warning)
        case .unknown: log("Central Manager: BT state unknown.", level: .warning)
        @unknown default: log("Central Manager: Unhandled BT state \(central.state.rawValue)", level: .warning)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        log("Central: Discovered '\(name)' (RSSI: \(RSSI.intValue)). ID: ...\(String(peripheral.identifier.uuidString.suffix(6)))")
        peerRSSICache[peripheral.identifier] = RSSI
        if connectingOrConnectedPeer == nil {
            log("Central: Attempting connect to '\(name)' (ID: \(String(peripheral.identifier.uuidString.prefix(8))))...") // CORRECTED
            connectingOrConnectedPeer = peripheral
            centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            if connectingOrConnectedPeer?.identifier != peripheral.identifier {
                 log("Central: Busy with \(String(describing: connectingOrConnectedPeer!.identifier.uuidString.prefix(8))). Ignoring diff peer '\(name)'.", level: .info) // CORRECTED
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Central: Connected to '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Discovering services...") // CORRECTED
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central: Connected UNEXPECTED peripheral (\(String(peripheral.identifier.uuidString.prefix(8)))) vs \(String(describing: connectingOrConnectedPeer?.identifier.uuidString.prefix(8))). Disconnecting.", level: .warning) // CORRECTED
            central.cancelPeripheralConnection(peripheral)
            if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil }
            return
        }
        peripheral.delegate = self
        peripheral.discoverServices([StreetPassBLE_UUIDs.streetPassServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)) // CORRECTED
        let errStr = error?.localizedDescription ?? "unknown reason"
        log("Central: Fail connect to '\(name)'. Error: \(errStr)", level: .error)
        if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil }
        delegate?.bleManagerDidEncounterError(.connectionFailed("Connect to '\(name)' fail: \(errStr)"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)) // CORRECTED
        let peerID = peripheral.identifier
        if let err = error {
            log("Central: Disconnected '\(name)' (ID: \(String(peerID.uuidString.prefix(8)))) error: \(err.localizedDescription)", level: .warning); delegate?.bleManagerDidEncounterError(.connectionFailed("Disconnect '\(name)': \(err.localizedDescription)")) // CORRECTED
        } else { log("Central: Disconnected clean '\(name)' (ID: \(String(peerID.uuidString.prefix(8)))).") } // CORRECTED
        for charUUID in StreetPassBLE_UUIDs.allCharacteristicUUIDs() {
            let bufferKey = PeripheralCharacteristicPair(peripheralID: peerID, characteristicID: charUUID)
            if incomingDataBuffers.removeValue(forKey: bufferKey) != nil { log("Central: Clear buffer \(name)/char \(String(charUUID.uuidString.prefix(8))) disconnect.") } // CORRECTED
        }
        if connectingOrConnectedPeer?.identifier == peerID { connectingOrConnectedPeer = nil }
        peerRSSICache.removeValue(forKey: peerID)
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central/PeerDelegate: Service discovery from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return } // CORRECTED
        if let err = error {
            log("Central/PeerDelegate: Error discovering services on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))': \(err.localizedDescription)", level: .error) // CORRECTED
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Svc discovery peer fail: \(err.localizedDescription)")); return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == StreetPassBLE_UUIDs.streetPassServiceUUID }) else {
            log("Central/PeerDelegate: StreetPass service (\(StreetPassBLE_UUIDs.streetPassServiceUUID.uuidString)) NOT FOUND on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Disconnecting.", level: .warning) // CORRECTED
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.serviceSetupFailed("StreetPass svc not found peer.")); return
        }
        log("Central/PeerDelegate: Found StreetPass service on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Discovering EncounterCard char...") // CORRECTED
        peripheral.discoverCharacteristics([StreetPassBLE_UUIDs.encounterCardCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central/PeerDelegate: Char discovery from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return } // CORRECTED
        if service.uuid != StreetPassBLE_UUIDs.streetPassServiceUUID {
            log("Central/PeerDelegate: Chars discovered for unexpected service \(service.uuid) on \(String(describing: peripheral.name)).", level: .warning); return } // CORRECTED
        if let err = error {
            log("Central/PeerDelegate: Error discovering chars for svc \(String(service.uuid.uuidString.prefix(8))) on '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .error) // CORRECTED
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Char discovery fail: \(err.localizedDescription)")); return
        }
        guard let cardChar = service.characteristics?.first(where: { $0.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID }) else {
            log("Central/PeerDelegate: EncounterCard char (\(StreetPassBLE_UUIDs.encounterCardCharacteristicUUID.uuidString)) NOT FOUND in svc \(String(service.uuid.uuidString.prefix(8))). Disconnecting.", level: .warning) // CORRECTED
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("EncounterCard char not found peer.")); return
        }
        // CORRECTED: Use propertiesString for logging CBCharacteristicProperties
        log("Central/PeerDelegate: Found EncounterCard characteristic. UUID: \(String(cardChar.uuid.uuidString.prefix(8))). Properties: \(cardChar.properties.description)") // CORRECTED
        if cardChar.properties.contains(.notify) {
            log("Central/PeerDelegate: Char supports Notify. Subscribing...")
            peripheral.setNotifyValue(true, for: cardChar)
        } else if cardChar.properties.contains(.read) {
            log("Central/PeerDelegate: Char no Notify, but supports Read. Reading...", level: .info)
            peripheral.readValue(for: cardChar)
        } else {
            log("Central/PeerDelegate: EncounterCard char no Notify/Read. Cannot exchange. Disconnecting.", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Peer card char unusable (no read/notify)."));
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
             log("Central/PeerDelegate: Notify state update for unexpected char/peripheral. Char: \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return } // CORRECTED
        if let err = error {
            log("Central/PeerDelegate: Error changing notify state CardData on \(String(describing: peripheral.name)): \(err.localizedDescription)", level: .error) // CORRECTED
            centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Subscribe peer card fail: \(err.localizedDescription)")); return
        }
        if characteristic.isNotifying {
            log("Central/PeerDelegate: SUBSCRIBED to peer card notify (\(String(characteristic.uuid.uuidString.prefix(8)))).") // CORRECTED
            log("Central/PeerDelegate: Sending our card to peer after subscribe...")
            attemptCardTransmissionToPeer(peripheral: peripheral, characteristic: characteristic)
        } else {
            log("Central/PeerDelegate: UNSUBSCRIBED from peer card notify (\(String(characteristic.uuid.uuidString.prefix(8)))).", level: .info) // CORRECTED
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Central/PeerDelegate: Write resp for unexpected char/peripheral. Char: \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return } // CORRECTED
        if let err = error {
            log("Central/PeerDelegate: Error WRITING our card to peer \(String(describing: peripheral.name)): \(err.localizedDescription)", level: .error) // CORRECTED
            delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Write local card to peer fail: \(err.localizedDescription)"));
        } else {
            log("Central/PeerDelegate: Successfully WROTE our card to peer \(String(describing: peripheral.name)).") // CORRECTED
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connectingOrConnectedPeer?.identifier == peripheral.identifier else {
            log("Central/PeerDelegate: Value update from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return } // CORRECTED
        let bufferKey = PeripheralCharacteristicPair(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
        if characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID {
            if let err = error {
                log("Central/PeerDelegate: Error char VALUE UPDATE \(String(characteristic.uuid.uuidString.prefix(8))): \(err.localizedDescription)", level: .error) // CORRECTED
                delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Receive value peer char fail: \(err.localizedDescription)"))
                incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil; return
            }
            guard let newDataChunk = characteristic.value else {
                log("Central/PeerDelegate: NIL data CardData from \(String(peripheral.identifier.uuidString.prefix(8))).", level: .warning); return } // CORRECTED
            log("Central/PeerDelegate: CHUNK (\(newDataChunk.count) bytes) for \(String(bufferKey.characteristicID.uuidString.prefix(8))) from \(String(bufferKey.peripheralID.uuidString.prefix(8))).") // CORRECTED
            var currentBuffer = incomingDataBuffers[bufferKey, default: Data()]
            currentBuffer.append(newDataChunk)
            incomingDataBuffers[bufferKey] = currentBuffer
            log("Central/PeerDelegate: Accumulated buffer for \(String(bufferKey.peripheralID.uuidString.prefix(8))) is now \(currentBuffer.count) bytes.") // CORRECTED
            do {
                let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: currentBuffer)
                log("Central/PeerDelegate: DECODED card from '\(receivedCard.displayName)'. Size: \(currentBuffer.count). Drawing: \(receivedCard.drawingData != nil).")
                let rssi = peerRSSICache[peripheral.identifier]; processAndStoreReceivedCard(receivedCard, rssi: rssi)
                incomingDataBuffers[bufferKey] = nil
                log("Central/PeerDelegate: Card exchange complete '\(peripheral.name ?? "")'. Disconnecting.")
                centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil
            } catch let decodingError as DecodingError {
                 switch decodingError {
                 case .dataCorrupted(let context): log("Central/PeerDelegate: Data CORRUPTED \(String(bufferKey.peripheralID.uuidString.prefix(8))). Buffer: \(currentBuffer.count). Context: \(context.debugDescription). Path: \(context.codingPath)", level: .error); log("Central/PeerDelegate: Snippet: \(String(data: currentBuffer.prefix(500), encoding: .utf8) ?? "Non-UTF8")"); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Data corrupted: \(context.debugDescription)")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
                 case .keyNotFound(let key, let context): log("Central/PeerDelegate: Key '\(key.stringValue)' NOT FOUND \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Missing key '\(key.stringValue)'.")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
                 case .typeMismatch(let type, let context): log("Central/PeerDelegate: Type MISMATCH '\(context.codingPath.last?.stringValue ?? "uk")' (exp \(type)) \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Type mismatch key '\(context.codingPath.last?.stringValue ?? "")': \(context.debugDescription).")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
                 case .valueNotFound(let type, let context): log("Central/PeerDelegate: Value NOT FOUND type \(type) key '\(context.codingPath.last?.stringValue ?? "uk")' \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Value not found key '\(context.codingPath.last?.stringValue ?? "")': \(context.debugDescription).")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
                 @unknown default: log("Central/PeerDelegate: Unknown decode error \(String(bufferKey.peripheralID.uuidString.prefix(8))). Error: \(decodingError.localizedDescription)", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Unknown decode error: \(decodingError.localizedDescription)")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
                 }
                 if case .dataCorrupted = decodingError {}
                 else if currentBuffer.count < 65535 { log("Central/PeerDelegate: Decode fail (not dataCorrupted), assume incomplete. Buffer: \(currentBuffer.count). Waiting more data for \(String(bufferKey.peripheralID.uuidString.prefix(8))).") } // CORRECTED
                 else { log("Central/PeerDelegate: Buffer too large (\(currentBuffer.count)) and still fail decode. Giving up \(String(bufferKey.peripheralID.uuidString.prefix(8))).", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Buffer limit exceeded decoding.")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil } // CORRECTED
            } catch {
                log("Central/PeerDelegate: GENERIC UNEXPECTED DECODE ERROR \(String(bufferKey.peripheralID.uuidString.prefix(8))). Buffer: \(currentBuffer.count). Error: \(error.localizedDescription)", level: .error); delegate?.bleManagerDidEncounterError(.dataDeserializationError("Generic error decode peer card: \(error.localizedDescription)")); incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral); connectingOrConnectedPeer = nil // CORRECTED
            }
        } else {
            log("Central/PeerDelegate: Updated value for unexpected characteristic: \(String(characteristic.uuid.uuidString.prefix(8))) from \(String(peripheral.identifier.uuidString.prefix(8)))") // CORRECTED
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard connectingOrConnectedPeer?.identifier == peripheral.identifier else { return }
        if let err = error { log("Central/PeerDelegate: Error reading RSSI for '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .warning); return }
        log("Central/PeerDelegate: Updated RSSI for '\(peripheral.name ?? "")' to \(RSSI.intValue).")
        peerRSSICache[peripheral.identifier] = RSSI
    }

    // MARK: - CBPeripheralManagerDelegate
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        delegate?.bleManagerDidUpdateState(bluetoothState: manager.state)
        switch manager.state {
        case .poweredOn: log("Peripheral Manager: Bluetooth ON."); setupServiceAndStartAdvertising()
        case .poweredOff: log("Peripheral Manager: Bluetooth OFF.", level: .warning); DispatchQueue.main.async { self.isAdvertising = false }; delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT Off (Peripheral)"))
        case .unauthorized: log("Peripheral Manager: BT unauthorized.", level: .error); delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT permissions not granted peripheral."))
        default: log("Peripheral Manager: State changed to \(manager.state.rawValue)", level: .info)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Error adding service \(String(service.uuid.uuidString.prefix(8))): \(err.localizedDescription)", level: .error); delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Fail add BLE svc: \(err.localizedDescription)")); return } // CORRECTED
        log("Peripheral/MgrDelegate: Service \(String(service.uuid.uuidString.prefix(8))) added. Attempting start advertising...") // CORRECTED
        actuallyStartAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Fail start advertising: \(err.localizedDescription)", level: .error); DispatchQueue.main.async { self.isAdvertising = false }; delegate?.bleManagerDidEncounterError(.advertisingFailed("Fail start advertising: \(err.localizedDescription)")); return }
        log("Peripheral/MgrDelegate: STARTED ADVERTISING StreetPass service.")
        DispatchQueue.main.async { self.isAdvertising = true }
        if let char = self.encounterCardMutableCharacteristic {
            do { let cardData = try jsonEncoder.encode(self.localUserCard); char.value = cardData; log("Peripheral/MgrDelegate: Set initial char value on ad start. Size: \(cardData.count).") }
            catch { log("Peripheral/MgrDelegate: Error encode card for initial char value: \(error.localizedDescription)", level: .error) }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let centralIDPart = String(request.central.identifier.uuidString.prefix(8))
        log("Peripheral/MgrDelegate: Read Request Char UUID \(String(request.characteristic.uuid.uuidString.prefix(8))) from Central \(centralIDPart). Offset: \(request.offset). Central Max Update: \(request.central.maximumUpdateValueLength)") // CORRECTED
        guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Peripheral/MgrDelegate: Read req UNKNOWN char (\(request.characteristic.uuid.uuidString)). Responding 'AttributeNotFound'.", level: .warning)
            manager.respond(to: request, withResult: .attributeNotFound); return
        }
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let fullCardData = try jsonEncoder.encode(cardToSend)
            log("Peripheral/MgrDelegate: Total card data size for read: \(fullCardData.count) bytes for Central \(centralIDPart).")
            if request.offset > fullCardData.count {
                log("Peripheral/MgrDelegate: Read offset (\(request.offset)) > data length (\(fullCardData.count)). Respond 'InvalidOffset'.", level: .warning)
                manager.respond(to: request, withResult: .invalidOffset); return
            }
            let remainingLength = fullCardData.count - request.offset
            let lengthToSend = min(remainingLength, request.central.maximumUpdateValueLength)
            let chunkToSend = fullCardData.subdata(in: request.offset ..< (request.offset + lengthToSend))
            request.value = chunkToSend
            log("Peripheral/MgrDelegate: Responding Central \(centralIDPart) with \(chunkToSend.count) bytes (offset \(request.offset)). Success.")
            manager.respond(to: request, withResult: .success)
        } catch {
            log("Peripheral/MgrDelegate: Error encoding local card for read response: \(error.localizedDescription)", level: .error)
            manager.respond(to: request, withResult: .unlikelyError)
            delegate?.bleManagerDidEncounterError(.dataSerializationError("Encode card read response fail: \(error.localizedDescription)"))
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let centralIDPart = String(request.central.identifier.uuidString.prefix(8))
            log("Peripheral/MgrDelegate: Write Request Char UUID \(String(request.characteristic.uuid.uuidString.prefix(8))) from Central \(centralIDPart). Length: \(request.value?.count ?? 0).") // CORRECTED
            guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
                log("Peripheral/MgrDelegate: Write UNKNOWN char from \(centralIDPart). Respond 'AttributeNotFound'.", level: .warning)
                manager.respond(to: request, withResult: .attributeNotFound); continue
            }
            guard let data = request.value, !data.isEmpty else {
                log("Peripheral/MgrDelegate: Write EMPTY data from \(centralIDPart). Respond 'InvalidAttributeValueLength'.", level: .warning)
                manager.respond(to: request, withResult: .invalidAttributeValueLength); continue
            }
            log("Peripheral/MgrDelegate: Received write data (\(data.count) bytes) Central \(centralIDPart). Decoding...")
            do {
                let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
                log("Peripheral/MgrDelegate: DECODED card from '\(receivedCard.displayName)' (Central \(centralIDPart)). Processing...", level: .info)
                processAndStoreReceivedCard(receivedCard, rssi: nil)
                manager.respond(to: request, withResult: .success)
            } catch {
                log("Peripheral/MgrDelegate: DECODING card Central \(centralIDPart) FAILED: \(error.localizedDescription). Size: \(data.count)", level: .error) // CORRECTED
                log("Peripheral/MgrDelegate: Data Snippet: \(String(data: data.prefix(500), encoding: .utf8) ?? "Non-UTF8 data")")
                manager.respond(to: request, withResult: .unlikelyError)
                delegate?.bleManagerDidEncounterError(.dataDeserializationError("Decode peer card write (Central \(centralIDPart)) fail: \(error.localizedDescription)"))
            }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Peripheral/MgrDelegate: Central \(String(central.identifier.uuidString.prefix(8))) subscribed unexpected char \(String(characteristic.uuid.uuidString.prefix(8)))", level: .warning); return } // CORRECTED
        let centralIDPart = String(central.identifier.uuidString.prefix(8))
        log("Peripheral/MgrDelegate: Central \(centralIDPart) SUBSCRIBED to EncounterCard char (\(String(characteristic.uuid.uuidString.prefix(8)))).") // CORRECTED
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central); log("Peripheral/MgrDelegate: Added Central \(centralIDPart) to subscribed list. Count: \(subscribedCentrals.count).")
        }
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            if manager.updateValue(cardData, for: self.encounterCardMutableCharacteristic!, onSubscribedCentrals: [central]) {
                log("Peripheral/MgrDelegate: Sent initial card data notify (\(cardData.count) bytes) to new subscriber \(centralIDPart).")
            } else {
                log("Peripheral/MgrDelegate: FAILED queue initial notify for \(centralIDPart) (buffer full). Size: \(cardData.count).", level: .warning)
            }
        } catch {
            log("Peripheral/MgrDelegate: Error encode card for initial notify to \(centralIDPart): \(error.localizedDescription)", level: .error)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else { return }
        let centralIDPart = String(central.identifier.uuidString.prefix(8))
        log("Peripheral/MgrDelegate: Central \(centralIDPart) UNSUBSCRIBED from EncounterCard char.")
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        log("Peripheral/MgrDelegate: Removed Central \(centralIDPart) from subscribed list. Count: \(subscribedCentrals.count).")
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        log("Peripheral/MgrDelegate: Peripheral manager ready to update subscribers again.")
    }
}

extension Data {
    func subdataIfAppropriate(offset: Int, maxLength: Int) -> Data? {
        guard offset >= 0 else { log_ble_data_helper("Invalid offset: \(offset)."); return nil }
        guard maxLength > 0 else { log_ble_data_helper("Invalid maxLength: \(maxLength)."); return nil }
        if offset > self.count { log_ble_data_helper("Offset \(offset) > data length \(self.count). Returning empty."); return Data() }
        if offset == self.count { log_ble_data_helper("Offset \(offset) == data length \(self.count). Returning empty."); return Data() }
        let availableLength = self.count - offset
        let lengthToReturn = Swift.min(availableLength, maxLength)
        let startIndex = self.index(self.startIndex, offsetBy: offset)
        let endIndex = self.index(startIndex, offsetBy: lengthToReturn)
        log_ble_data_helper("Subdata: Total \(self.count), Offset \(offset), MaxLengthCentral \(maxLength), Available \(availableLength), Return \(lengthToReturn).")
        return self.subdata(in: startIndex..<endIndex)
    }
}

// CORRECTED: Extension for CBCharacteristicProperties to get a descriptive string
extension CBCharacteristicProperties {
    var description: String {
        var descriptions: [String] = []
        if contains(.broadcast) { descriptions.append("broadcast") }
        if contains(.read) { descriptions.append("read") }
        if contains(.writeWithoutResponse) { descriptions.append("writeWithoutResponse") }
        if contains(.write) { descriptions.append("write") }
        if contains(.notify) { descriptions.append("notify") }
        if contains(.indicate) { descriptions.append("indicate") }
        if contains(.authenticatedSignedWrites) { descriptions.append("authenticatedSignedWrites") }
        if contains(.extendedProperties) { descriptions.append("extendedProperties") }
        if contains(.notifyEncryptionRequired) { descriptions.append("notifyEncryptionRequired") }
        if contains(.indicateEncryptionRequired) { descriptions.append("indicateEncryptionRequired") }
        return descriptions.joined(separator: ", ")
    }
}

fileprivate func log_ble_data_helper(_ message: String) {
    print("StreetPassBLE/DataHelper: \(message)")
}
