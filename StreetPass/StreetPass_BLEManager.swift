// StreetPass_BLEManager.swift
import Foundation
import CoreBluetooth
import Combine

// THIS IS THE FIRST FIX
@MainActor
protocol StreetPassBLEManagerDelegate: AnyObject {
    func bleManagerDidUpdateState(bluetoothState: CBManagerState)
    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?)
    func bleManagerDidUpdateLog(_ message: String)
    func bleManagerDidEncounterError(_ error: StreetPassBLEError)
}

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

struct StreetPassBLE_UUIDs {
    static let streetPassServiceUUID_String = "DEADBEEF-1234-5678-9ABC-DEF012345678" // // classic
    static let encounterCardCharacteristicUUID_String = "CAFEF00D-0000-1111-2222-333344445555" // // also classic
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

// For central sending chunks to peripheral
fileprivate struct ChunkedWriteOperation {
    let peripheralID: UUID
    let characteristicID: CBUUID
    let totalData: Data
    var currentOffset: Int = 0
    let chunkSize: Int // // this should be peripheral.maximumWriteValueLength

    var hasMoreChunks: Bool {
        return currentOffset < totalData.count
    }

    mutating func nextChunk() -> Data? {
        guard hasMoreChunks else { return nil }
        let end = min(currentOffset + chunkSize, totalData.count)
        let chunk = totalData.subdata(in: currentOffset..<end)
        currentOffset = end
        return chunk
    }

    init(peripheralID: UUID, characteristicID: CBUUID, data: Data, chunkSize: Int = 100) { // default 100 is small, will be updated
        self.peripheralID = peripheralID
        self.characteristicID = characteristicID
        self.totalData = data
        self.chunkSize = chunkSize
    }
}

// // NEW: For peripheral sending chunks via notifications
fileprivate struct PeripheralChunkSendOperation {
    let central: CBCentral // // need this to get maximumUpdateValueLength
    let characteristicUUID: CBUUID // // should be encounterCardCharacteristicUUID
    let totalData: Data
    var currentOffset: Int = 0
    // chunkSize determined by central.maximumUpdateValueLength

    var hasMoreChunks: Bool {
        return currentOffset < totalData.count
    }

    mutating func nextChunk() -> Data? {
        guard hasMoreChunks else { return nil }
        let chunkSizeForThisCentral = central.maximumUpdateValueLength // // crucial!
        let end = min(currentOffset + chunkSizeForThisCentral, totalData.count)
        let chunk = totalData.subdata(in: currentOffset..<end)
        currentOffset = end
        return chunk
    }

    init(central: CBCentral, characteristicUUID: CBUUID, data: Data) {
        self.central = central
        self.characteristicUUID = characteristicUUID
        self.totalData = data
    }
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
    private var subscribedCentrals: [CBCentral] = [] // // list of centrals subscribed to our characteristic

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { (decoder) -> Date in
            let container = try decoder.singleValueContainer()
            if let dateString = try? container.decode(String.self) {
                let isoFormatters = [
                    ISO8601DateFormatter(),
                    { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                    { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
                ]
                for formatter in isoFormatters {
                    if let date = formatter.date(from: dateString) { return date }
                }
                let commonFormatters = [
                    { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
                    { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"; f.locale = Locale(identifier: "en_US_POSIX"); return f }(),
                ]
                for formatter in commonFormatters {
                    if let date = (formatter as AnyObject).date(from: dateString) { return date } // // casting to anyobject for date(from:) ? tf???
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
    private let encounterDebounceInterval: TimeInterval = 60 // // 1 min debounce
    private let localUserCardStorageKey = "streetPass_LocalUserCard_v2"
    private let receivedCardsStorageKey = "streetPass_ReceivedCards_v2"
    
    // Buffers for incoming data
    private var incomingDataBuffers: [PeripheralCharacteristicPair: Data] = [:] // For central receiving data
    private var incomingWriteBuffers: [UUID: Data] = [:] // // NEW: For peripheral receiving writes from central, keyed by central.identifier

    // Outgoing data operations
    private var currentChunkedWrite: ChunkedWriteOperation? // For central sending data
    private var ongoingNotificationSends: [UUID: PeripheralChunkSendOperation] = [:] // // NEW: For peripheral sending notifications, keyed by central.identifier

    init(userID: String) {
        self.localUserCard = EncounterCard(userID: userID)
        super.init()
        log("blemanager: init - about to create centralmanager") // <--- new log
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        log("blemanager: init - centralmanager created. about to create peripheralmanager") // <--- new log
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        log("blemanager: init - peripheralmanager created.") // <--- new log
        log("StreetPass BLE Manager initialized for UserID: \(userID). Waiting for Bluetooth power state.") // keep this one too
        loadLocalUserCardFromPersistence()
        loadReceivedCardsFromPersistence()
    }
    func log(_ message: String, level: LogLevel = .info) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let prefix: String
            switch level {
            case .error: prefix = "err! >" // // more aesthetic errors
            case .warning: prefix = "warn >"
            case .info: prefix = "info >"
            }
            let fullMessage = "\(timestamp) \(prefix) \(message)"
            print("StreetPassBLE: \(fullMessage)")
            self.activityLog.insert(fullMessage, at: 0)
            if self.activityLog.count > 250 { // // keep log manageable
                self.activityLog.removeLast(self.activityLog.count - 250)
            }
            self.delegate?.bleManagerDidUpdateLog(fullMessage)
        }
    }
    enum LogLevel { case info, warning, error }

    public func start() {
        log("request to start streetpass services.") // lowercase
        if let peer = connectingOrConnectedPeer {
            log("start called, cancelling existing connection to \(String(describing: peer.identifier.uuidString.prefix(8)))", level: .warning)
            centralManager.cancelPeripheralConnection(peer)
            connectingOrConnectedPeer = nil
        }
        if centralManager.state == .poweredOn { startScanning() }
        else { log("central manager not powered on. scan deferred.", level: .warning) } // lowercase
        if peripheralManager.state == .poweredOn { setupServiceAndStartAdvertising() }
        else { log("peripheral manager not powered on. advertising deferred.", level: .warning) } // lowercase
    }

    public func stop() {
        log("request to stop streetpass services.") // lowercase
        stopScanning()
        stopAdvertising()
        if let peer = connectingOrConnectedPeer {
            log("stop called, cancelling active connection to peer: \(String(describing: peer.identifier.uuidString.prefix(8)))")
            centralManager.cancelPeripheralConnection(peer)
            connectingOrConnectedPeer = nil
        }
        // // clear ongoing sends too
        ongoingNotificationSends.removeAll()
        currentChunkedWrite = nil
    }

    public func updateLocalUserCard(newCard: EncounterCard) {
        guard newCard.userID == self.localUserCard.userID else {
            log("Critical error: Attempt to update card with mismatched UserID. Current: \(self.localUserCard.userID), New: \(newCard.userID)", level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.internalInconsistency("UserID mismatch during card update.")) }
            return
        }
        let contentActuallyChanged = self.localUserCard.isContentDifferent(from: newCard)
        self.localUserCard = newCard
        if contentActuallyChanged || self.localUserCard.id == EncounterCard(userID: self.localUserCard.userID).id { // // what is this id comparison for?
            self.localUserCard.id = UUID()
        }
        self.localUserCard.lastUpdated = Date()
        log("Local user card updated. DisplayName: '\(self.localUserCard.displayName)'. NewID: \(self.localUserCard.id). Drawing size: \(self.localUserCard.drawingData?.count ?? 0) bytes. Content changed: \(contentActuallyChanged).")
        saveLocalUserCardToPersistence()
        
        // // update characteristic value and notify subscribers IF advertising and char exists
        if isAdvertising, let characteristic = self.encounterCardMutableCharacteristic {
            do {
                let cardData = try jsonEncoder.encode(self.localUserCard)
                characteristic.value = cardData // // this might be too large for a single value, but iOS handles reads in chunks. For notifications, we now handle it.
                log("Updated characteristic value in peripheral for reads. Size: \(cardData.count) bytes.")
                
                // // NEW: Initiate/update chunked send for all subscribed centrals
                if !subscribedCentrals.isEmpty {
                    log("triggering chunked notification send to \(subscribedCentrals.count) central(s) for local card update...")
                    for central in subscribedCentrals {
                        ongoingNotificationSends[central.identifier] = PeripheralChunkSendOperation(
                            central: central,
                            characteristicUUID: characteristic.uuid,
                            data: cardData
                        )
                        attemptToSendNextNotificationChunk(for: central.identifier)
                    }
                }
            } catch {
                let errorMsg = "Encoding local card for characteristic update/notification failed: \(error.localizedDescription)"
                log(errorMsg, level: .error)
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
            }
        }
        objectWillChange.send()
    }
    
    // // NEW: Helper to send notification chunks
    private func attemptToSendNextNotificationChunk(for centralIdentifier: UUID) {
        guard var sendOperation = ongoingNotificationSends[centralIdentifier],
              let characteristic = self.encounterCardMutableCharacteristic else {
            // log("no ongoing notification send for central \(centralIdentifier) or char missing.", level: .info) // too noisy
            ongoingNotificationSends.removeValue(forKey: centralIdentifier)
            return
        }

        guard sendOperation.hasMoreChunks else {
            log("all notification chunks sent to central \(String(centralIdentifier.uuidString.prefix(8))). operation complete.", level: .info)
            ongoingNotificationSends.removeValue(forKey: centralIdentifier)
            return
        }

        if let chunk = sendOperation.nextChunk() {
            log("peripheral: sending notify chunk (\(chunk.count) bytes, offset \(sendOperation.currentOffset - chunk.count)) to central \(String(centralIdentifier.uuidString.prefix(8))).")
            let success = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: [sendOperation.central])
            
            if success {
                ongoingNotificationSends[centralIdentifier] = sendOperation // // update offset in stored operation
                if sendOperation.hasMoreChunks {
                    // // yield to main thread to prevent recursion depth / blocking, and to allow isReadyToUpdateSubscribers to take over if needed
                    DispatchQueue.main.async {
                        self.attemptToSendNextNotificationChunk(for: centralIdentifier)
                    }
                } else {
                    log("peripheral: finished sending all notification chunks to central \(String(centralIdentifier.uuidString.prefix(8))).")
                    ongoingNotificationSends.removeValue(forKey: centralIdentifier)
                }
            } else {
                log("peripheral: updatevalue returned false for central \(String(centralIdentifier.uuidString.prefix(8))). will retry on isreadytoupdatesubscribers.", level: .warning)
                // // Don't remove the operation, peripheralManagerIsReady(toUpdateSubscribers:) will retry.
                // // The offset in sendOperation is not advanced here, so it will resend the same chunk.
            }
        } else { // // should be caught by hasMoreChunks guard
             log("peripheral: no more chunks (or chunk gen failed) for central \(String(centralIdentifier.uuidString.prefix(8))).", level: .warning)
             ongoingNotificationSends.removeValue(forKey: centralIdentifier)
        }
    }


    private func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Central: Bluetooth not powered on. Scan deferred.", level: .warning); return
        }
        if isScanning { log("Central: Already scanning."); return }
        log("Central: Starting scan for StreetPass service: \(StreetPassBLE_UUIDs.streetPassServiceUUID.uuidString)")
        centralManager.scanForPeripherals(withServices: [StreetPassBLE_UUIDs.streetPassServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]) // // allow dupes for rssi updates
        DispatchQueue.main.async { self.isScanning = true }
    }

    private func stopScanning() {
        if centralManager.isScanning { centralManager.stopScan(); log("Central: Scanning stopped.") }
        DispatchQueue.main.async { self.isScanning = false }
    }

    private func setupServiceAndStartAdvertising() {
        log("blemanager: setupserviceandstartadvertising CALLED. current state: \(peripheralManager.state.rawValue)") // <--- new log
        guard peripheralManager.state == .poweredOn else {
            log("Peripheral: Bluetooth not powered on. Service setup deferred.", level: .warning); return
        }
        if encounterCardMutableCharacteristic != nil && peripheralManager.isAdvertising {
             log("Peripheral: Service likely configured and already advertising.")
             return
        }
        if encounterCardMutableCharacteristic != nil && !peripheralManager.isAdvertising {
             log("Peripheral: Service likely configured, but not advertising. Starting advertising...")
             actuallyStartAdvertising() // // just start it
             return
        }
        log("Peripheral: Setting up Encounter Card service...")
        encounterCardMutableCharacteristic = CBMutableCharacteristic( // // this is THE characteristic
            type: StreetPassBLE_UUIDs.encounterCardCharacteristicUUID,
            properties: [.read, .write, .notify], // // can read, write, and get notified
            value: nil, // // initial value set later or on read
            permissions: [.readable, .writeable] // // app can read and write it
        )
        let service = CBMutableService(type: StreetPassBLE_UUIDs.streetPassServiceUUID, primary: true)
        service.characteristics = [encounterCardMutableCharacteristic!]
        peripheralManager.removeAllServices() // // clean slate
        log("Peripheral: Adding service \(service.uuid.uuidString)...")
        peripheralManager.add(service) // // this is async, wait for didAdd
    }
    
    private func actuallyStartAdvertising() {
        log("blemanager: actuallystartadvertising CALLED. isadvertising already? \(isAdvertising)") // <--- new log
        if isAdvertising { log("Peripheral: Already advertising or start attempt in progress.", level: .info); return }
        let advertisementData: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [StreetPassBLE_UUIDs.streetPassServiceUUID]]

        log("Peripheral: Starting advertising with data: \(advertisementData)")
        peripheralManager.startAdvertising(advertisementData) // // also async
    }

    private func stopAdvertising() {
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising(); log("Peripheral: Advertising stopped.") }
        DispatchQueue.main.async { self.isAdvertising = false }
        ongoingNotificationSends.removeAll() // // stop any pending sends
    }
    
    private func processAndStoreReceivedCard(_ card: EncounterCard, rssi: NSNumber?) {
        let now = Date()
        if let lastTime = lastEncounterTimeByUser[card.userID], now.timeIntervalSince(lastTime) < encounterDebounceInterval {
            log("Debounced: Card from UserID '\(card.userID)' (Name: \(card.displayName)) received again within \(encounterDebounceInterval)s. Last: \(formatTimestampForLog(lastTime)). Ignoring.", level: .info)
            return // // too soon, junior
        }
        DispatchQueue.main.async { // // ui updates on main thread
            var cardUpdatedInList = false
            if let index = self.receivedCards.firstIndex(where: { $0.userID == card.userID }) {
                // // card exists, check if newer
                if card.lastUpdated > self.receivedCards[index].lastUpdated || card.cardSchemaVersion > self.receivedCards[index].cardSchemaVersion {
                    self.receivedCards[index] = card // // update it
                    cardUpdatedInList = true
                    self.log("Updated card for UserID: '\(card.userID)' (Name: \(card.displayName)). Drawing: \(card.drawingData != nil).")
                } else {
                    self.log("Received card for UserID: '\(card.userID)' (Name: \(card.displayName)) is not newer. No UI update made. Drawing: \(card.drawingData != nil).")
                    self.lastEncounterTimeByUser[card.userID] = now // // still update debounce time
                    return
                }
            } else {
                // // new card
                self.receivedCards.append(card)
                cardUpdatedInList = true
                self.log("Added new card from UserID: '\(card.userID)' (Name: \(card.displayName)). Drawing: \(card.drawingData != nil).")
            }
            if cardUpdatedInList {
                self.receivedCards.sort(by: { $0.lastUpdated > $1.lastUpdated }) // // keep sorted
                self.saveReceivedCardsToPersistence()
                self.lastEncounterTimeByUser[card.userID] = now
                self.delegate?.bleManagerDidReceiveCard(card, rssi: rssi) // // notify delegate (viewmodel)
            }
        }
    }

    private func formatTimestampForLog(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss.SSS"; return formatter.string(from: date)
    }

    // MARK: - Persistence
    func loadLocalUserCardFromPersistence() {
        log("Loading local user card from persistence...")
        guard let data = UserDefaults.standard.data(forKey: localUserCardStorageKey) else {
            log("No local user card found in persistence. Saving current default/newly initialized card.")
            saveLocalUserCardToPersistence(); return
        }
        do {
            var loadedCard = try jsonDecoder.decode(EncounterCard.self, from: data)
            if loadedCard.userID == self.localUserCard.userID { // // check if it's for current app user
                if loadedCard.cardSchemaVersion < EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion {
                    log("Loaded card schema (\(loadedCard.cardSchemaVersion)) is older. Updating to current schema (\(EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion)).", level: .warning)
                    // // migration logic could go here if fields changed
                    loadedCard.cardSchemaVersion = EncounterCard(userID: self.localUserCard.userID).cardSchemaVersion
                }
                self.localUserCard = loadedCard
                log("Successfully loaded local user card: '\(self.localUserCard.displayName)'. Schema: v\(self.localUserCard.cardSchemaVersion). Drawing: \(self.localUserCard.drawingData != nil)")
            } else {
                log("Persisted card UserID (\(loadedCard.userID)) MISMATCHES current (\(self.localUserCard.userID)). Resetting.", level: .error)
                // // this should ideally not happen if userID is persistent per device install
                self.localUserCard = EncounterCard(userID: self.localUserCard.userID) // // reset to default for this user
                saveLocalUserCardToPersistence()
            }
        } catch {
            let errorMsg = "Decoding local user card failed: \(error.localizedDescription). Using default and resaving."
            log(errorMsg, level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg)) }
            self.localUserCard = EncounterCard(userID: self.localUserCard.userID) // // fallback to default
            saveLocalUserCardToPersistence()
        }
        DispatchQueue.main.async { self.objectWillChange.send() } // // tell swiftui
    }

    private func saveLocalUserCardToPersistence() {
        do {
            let cardData = try jsonEncoder.encode(localUserCard)
            UserDefaults.standard.set(cardData, forKey: localUserCardStorageKey)
            log("Saved local user card ('\(localUserCard.displayName)', ID: \(String(localUserCard.id.uuidString.prefix(8)))) to UserDefaults. Size: \(cardData.count) bytes.")
        } catch {
            let errorMsg = "Encoding local user card for persistence failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
        }
    }

    private func loadReceivedCardsFromPersistence() {
        log("Loading received cards from persistence...")
        guard let data = UserDefaults.standard.data(forKey: receivedCardsStorageKey) else {
            log("No received cards found in persistence."); self.receivedCards = []; return
        }
        do {
            let loadedCards = try jsonDecoder.decode([EncounterCard].self, from: data)
            self.receivedCards = loadedCards.sorted(by: { $0.lastUpdated > $1.lastUpdated }) // // sort again just in case
            log("Loaded \(self.receivedCards.count) received cards from persistence.")
            // // repopulate debounce timer for loaded cards
            for card in self.receivedCards { self.lastEncounterTimeByUser[card.userID] = card.lastUpdated }
        } catch {
            let errorMsg = "Decoding received cards failed: \(error.localizedDescription). Clearing cache."; log(errorMsg, level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError(errorMsg)) }
            self.receivedCards = []
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    private func saveReceivedCardsToPersistence() {
        let maxReceivedCardsToSave = 50 // // don't let it grow infinitely
        let cardsToSave = Array(receivedCards.prefix(maxReceivedCardsToSave))
        do {
            let receivedData = try jsonEncoder.encode(cardsToSave)
            UserDefaults.standard.set(receivedData, forKey: receivedCardsStorageKey)
            log("Saved \(cardsToSave.count) received cards to UserDefaults. Size: \(receivedData.count) bytes.")
        } catch {
            let errorMsg = "Encoding received cards failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
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
    
    // MARK: - Central Role: Sending Data (Writing to Peer)
    private func attemptCardTransmissionToPeer(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else {
            log("Central: Peer's CardData char (\(String(characteristic.uuid.uuidString.prefix(8)))) no-write. No send.", level: .warning); return
        }
        if let activeWrite = currentChunkedWrite, activeWrite.peripheralID == peripheral.identifier, activeWrite.characteristicID == characteristic.uuid {
            log("Central: Chunked write already in progress for \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))). Ignoring new request.", level: .warning)
            return // // already sending to this guy
        }
        log("Central: Prep send our card to Peer: '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'.")
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date() // // always fresh timestamp
            let cardData = try jsonEncoder.encode(cardToSend)
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            
            let maxSingleWriteSize = peripheral.maximumWriteValueLength(for: writeType) // // important!
            log("Central: Max write value for peer \(String(peripheral.identifier.uuidString.prefix(8))) is \(maxSingleWriteSize) for type \(writeType == .withResponse ? "Resp" : "NoResp"). Card size: \(cardData.count).")

            // // always use withResponse if available for chunking, it's more reliable
            let actualWriteTypeForChunking = characteristic.properties.contains(.write) ? CBCharacteristicWriteType.withResponse : CBCharacteristicWriteType.withoutResponse
            let chunkSizeForWriting = peripheral.maximumWriteValueLength(for: actualWriteTypeForChunking)

            if cardData.count > chunkSizeForWriting { // // if card is bigger than what peripheral can take in one go
                log("Central: Card data (\(cardData.count) bytes) is large. Initiating CHUNKED WRITE. Max chunk: \(chunkSizeForWriting) bytes. Type: \(actualWriteTypeForChunking == .withResponse ? "Resp" : "NoResp")")
                currentChunkedWrite = ChunkedWriteOperation(
                    peripheralID: peripheral.identifier,
                    characteristicID: characteristic.uuid,
                    data: cardData,
                    chunkSize: chunkSizeForWriting // // use the actual max size
                )
                sendNextChunk(peripheral: peripheral, characteristic: characteristic, writeType: actualWriteTypeForChunking)
            } else {
                // // small enough for one shot
                log("Central: Writing our card (\(cardData.count) bytes) in ONE SHOT to \(String(characteristic.uuid.uuidString.prefix(8))) type \(writeType == .withResponse ? "Resp" : "NoResp").")
                currentChunkedWrite = nil // // no chunk op needed
                peripheral.writeValue(cardData, for: characteristic, type: writeType) // // use original preferred write type
                 if writeType == .withoutResponse {
                    log("Central: Sent card with .withoutResponse. Assuming success (no callback).")
                    // // might wanna disconnect here or wait a bit then disconnect if this is the end of interaction
                }
            }
        } catch {
            let errorMsg = "Encoding local card for transmission failed: \(error.localizedDescription)"; log(errorMsg, level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataSerializationError(errorMsg)) }
            currentChunkedWrite = nil // // clear op on error
        }
    }

    private func sendNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic, writeType: CBCharacteristicWriteType) {
        guard var writeOp = currentChunkedWrite, // // make it var to update offset
              writeOp.peripheralID == peripheral.identifier,
              writeOp.characteristicID == characteristic.uuid else {
            log("Central: No active chunked write operation or mismatch. Aborting sendNextChunk.", level: .warning)
            currentChunkedWrite = nil; return
        }
        if let chunk = writeOp.nextChunk() { // // this advances offset in writeOp
            currentChunkedWrite = writeOp // // store mutated op back
            log("Central: Sending chunk \((writeOp.currentOffset / writeOp.chunkSize) + (writeOp.currentOffset % writeOp.chunkSize == 0 ? 0 : 1)) of \((writeOp.totalData.count + writeOp.chunkSize - 1) / writeOp.chunkSize). Offset: \(writeOp.currentOffset - chunk.count), Size: \(chunk.count) bytes. Type: \(writeType == .withResponse ? "Resp" : "NoResp").")
            peripheral.writeValue(chunk, for: characteristic, type: writeType) // // use specified write type
            if writeType == .withoutResponse && !writeOp.hasMoreChunks { // // if no response and it was the last chunk
                 log("Central: Last chunk sent with .withoutResponse. Assuming success for operation.")
                 currentChunkedWrite = nil // // operation complete
            }
        } else {
            log("Central: All chunks sent successfully for write operation to \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))).")
            currentChunkedWrite = nil // // operation complete
            // // if writeType was .withResponse, didWriteValueFor will confirm the last one.
            // // if it was .withoutResponse, we assume it's done here.
        }
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.isBluetoothPoweredOn = (central.state == .poweredOn)
            self.delegate?.bleManagerDidUpdateState(bluetoothState: central.state)
        }
        switch central.state {
        case .poweredOn: log("Central Manager: Bluetooth ON."); startScanning()
        case .poweredOff:
            log("Central Manager: Bluetooth OFF.", level: .warning)
            DispatchQueue.main.async {
                self.isScanning = false
                self.delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT Off (Central)"))
            }
            if let peer = connectingOrConnectedPeer { log("Central: BT off, cancel connect to \(String(peer.identifier.uuidString.prefix(8)))", level: .warning); centralManager.cancelPeripheralConnection(peer); connectingOrConnectedPeer = nil; currentChunkedWrite = nil }
        case .unauthorized:
            log("Central Manager: BT unauthorized.", level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT permissions not granted.")) }
        case .unsupported:
            log("Central Manager: BT unsupported.", level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT LE not supported.")) }
        case .resetting: log("Central Manager: BT resetting.", level: .warning); if let peer = connectingOrConnectedPeer { centralManager.cancelPeripheralConnection(peer); connectingOrConnectedPeer = nil; currentChunkedWrite = nil }
        case .unknown: log("Central Manager: BT state unknown.", level: .warning)
        @unknown default: log("Central Manager: Unhandled BT state \(central.state.rawValue)", level: .warning)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown Device"
        log("Central: Discovered '\(name)' (RSSI: \(RSSI.intValue)). ID: ...\(String(peripheral.identifier.uuidString.suffix(6)))")
        peerRSSICache[peripheral.identifier] = RSSI
        if connectingOrConnectedPeer == nil { // // if not already busy
            log("Central: Attempting connect to '\(name)' (ID: \(String(peripheral.identifier.uuidString.prefix(8))))...")
            connectingOrConnectedPeer = peripheral // // mark as busy with this one
            centralManager.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        } else {
            if connectingOrConnectedPeer?.identifier != peripheral.identifier { // // busy with someone else
                 log("Central: Busy with \(String(describing: connectingOrConnectedPeer!.identifier.uuidString.prefix(8))) (\(connectingOrConnectedPeer?.name ?? "N/A")). Ignoring diff peer '\(name)'.", level: .info)
            }
            // // if it's the same peer we are trying to connect to, this is just a rescan, ignore.
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("Central: Connected to '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Discovering services...")
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central: Connected UNEXPECTED peripheral (\(String(peripheral.identifier.uuidString.prefix(8)))) vs \(String(describing: connectingOrConnectedPeer?.identifier.uuidString.prefix(8))). Disconnecting.", level: .warning)
            central.cancelPeripheralConnection(peripheral)
            // // do not clear connectingOrConnectedPeer here, might be a race. Let didDisconnect handle it.
            return
        }
        peripheral.delegate = self // // i am your delegate now
        peripheral.discoverServices([StreetPassBLE_UUIDs.streetPassServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8))
        let errStr = error?.localizedDescription ?? "unknown reason"
        log("Central: Fail connect to '\(name)'. Error: \(errStr)", level: .error)
        if connectingOrConnectedPeer?.identifier == peripheral.identifier { connectingOrConnectedPeer = nil; currentChunkedWrite = nil } // // no longer busy with this one
        DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.connectionFailed("Connect to '\(name)' fail: \(errStr)")) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let name = peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8))
        let peerID = peripheral.identifier
        if let err = error {
            log("Central: Disconnected '\(name)' (ID: \(String(peerID.uuidString.prefix(8)))) error: \(err.localizedDescription)", level: .warning)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.connectionFailed("Disconnect '\(name)': \(err.localizedDescription)")) }
        } else { log("Central: Disconnected clean '\(name)' (ID: \(String(peerID.uuidString.prefix(8)))).") }
        
        // // Clean up resources associated with this peripheral
        for charUUID in StreetPassBLE_UUIDs.allCharacteristicUUIDs() {
            let bufferKey = PeripheralCharacteristicPair(peripheralID: peerID, characteristicID: charUUID)
            if incomingDataBuffers.removeValue(forKey: bufferKey) != nil { log("Central: Clear buffer \(name)/char \(String(charUUID.uuidString.prefix(8))) disconnect.") }
        }
        if currentChunkedWrite?.peripheralID == peerID {
            log("Central: Clearing active chunked write operation for disconnected peripheral \(name).", level: .warning)
            currentChunkedWrite = nil
        }
        if connectingOrConnectedPeer?.identifier == peerID { connectingOrConnectedPeer = nil } // // no longer busy
        peerRSSICache.removeValue(forKey: peerID)
    }

    // MARK: - CBPeripheralDelegate (Central Role)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central/PeerDelegate: Service discovery from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return }
        if let err = error {
            log("Central/PeerDelegate: Error discovering services on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))': \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); // connectingOrConnectedPeer = nil; // let didDisconnect handle this
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Svc discovery peer fail: \(err.localizedDescription)")) }
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == StreetPassBLE_UUIDs.streetPassServiceUUID }) else {
            log("Central/PeerDelegate: StreetPass service (\(StreetPassBLE_UUIDs.streetPassServiceUUID.uuidString)) NOT FOUND on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Disconnecting.", level: .warning)
            centralManager.cancelPeripheralConnection(peripheral); // connectingOrConnectedPeer = nil;
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.serviceSetupFailed("StreetPass svc not found peer.")) }
            return
        }
        log("Central/PeerDelegate: Found StreetPass service on '\(peripheral.name ?? String(peripheral.identifier.uuidString.prefix(8)))'. Discovering EncounterCard char...")
        peripheral.discoverCharacteristics([StreetPassBLE_UUIDs.encounterCardCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier else {
            log("Central/PeerDelegate: Char discovery from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return }
        if service.uuid != StreetPassBLE_UUIDs.streetPassServiceUUID {
            log("Central/PeerDelegate: Chars discovered for unexpected service \(service.uuid) on \(String(describing: peripheral.name)).", level: .warning); return }
        if let err = error {
            log("Central/PeerDelegate: Error discovering chars for svc \(String(service.uuid.uuidString.prefix(8))) on '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); // connectingOrConnectedPeer = nil;
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Char discovery fail: \(err.localizedDescription)")) }
            return
        }
        guard let cardChar = service.characteristics?.first(where: { $0.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID }) else {
            log("Central/PeerDelegate: EncounterCard char (\(StreetPassBLE_UUIDs.encounterCardCharacteristicUUID.uuidString)) NOT FOUND in svc \(String(service.uuid.uuidString.prefix(8))). Disconnecting.", level: .warning)
            centralManager.cancelPeripheralConnection(peripheral); // connectingOrConnectedPeer = nil;
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("EncounterCard char not found peer.")) }
            return
        }
        log("Central/PeerDelegate: Found EncounterCard characteristic. UUID: \(String(cardChar.uuid.uuidString.prefix(8))). Properties: \(cardChar.properties.description)")
        
        // Exchange logic: 1. Subscribe (if notify), 2. Read (if no notify but read), 3. Write our card
        if cardChar.properties.contains(.notify) {
            log("Central/PeerDelegate: Char supports Notify. Subscribing...")
            peripheral.setNotifyValue(true, for: cardChar)
        } else if cardChar.properties.contains(.read) {
            log("Central/PeerDelegate: Char no Notify, but supports Read. Reading...", level: .info)
            peripheral.readValue(for: cardChar)
            log("Central/PeerDelegate: Attempting to send our card after initiating read...")
            attemptCardTransmissionToPeer(peripheral: peripheral, characteristic: cardChar)
        } else {
            log("Central/PeerDelegate: EncounterCard char no Notify/Read. Cannot receive their card. Still attempting to send ours.", level: .warning)
            if cardChar.properties.contains(.write) || cardChar.properties.contains(.writeWithoutResponse) {
                attemptCardTransmissionToPeer(peripheral: peripheral, characteristic: cardChar)
            } else {
                 log("Central/PeerDelegate: EncounterCard char also not writable. Full exchange impossible. Disconnecting.", level: .error)
                 centralManager.cancelPeripheralConnection(peripheral)
                 DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Peer card char unusable (no read/notify/write).")) }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
             log("Central/PeerDelegate: Notify state update for unexpected char/peripheral. Char: \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return }
        if let err = error {
            log("Central/PeerDelegate: Error changing notify state CardData on \(String(describing: peripheral.name)): \(err.localizedDescription)", level: .error)
            centralManager.cancelPeripheralConnection(peripheral); // connectingOrConnectedPeer = nil;
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Subscribe peer card fail: \(err.localizedDescription)")) }
            return
        }
        if characteristic.isNotifying {
            log("Central/PeerDelegate: SUBSCRIBED to peer card notify (\(String(characteristic.uuid.uuidString.prefix(8)))).")
            log("Central/PeerDelegate: Sending our card to peer after subscribe/simultaneously with read...")
            attemptCardTransmissionToPeer(peripheral: peripheral, characteristic: characteristic)
        } else {
            log("Central/PeerDelegate: UNSUBSCRIBED from peer card notify (\(String(characteristic.uuid.uuidString.prefix(8)))).", level: .info)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let activeWriteOp = currentChunkedWrite,
           activeWriteOp.peripheralID == peripheral.identifier,
           activeWriteOp.characteristicID == characteristic.uuid {
            if let err = error {
                log("Central/PeerDelegate: Error WRITING CHUNK to peer \(String(describing: peripheral.name)): \(err.localizedDescription)", level: .error)
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Chunk write to peer fail: \(err.localizedDescription)")) }
                currentChunkedWrite = nil
                return
            }
            log("Central/PeerDelegate: Successfully WROTE CHUNK (offset now \(activeWriteOp.currentOffset)) to peer \(String(describing: peripheral.name)).")
            sendNextChunk(peripheral: peripheral, characteristic: characteristic, writeType: .withResponse)
        } else {
            guard peripheral.identifier == connectingOrConnectedPeer?.identifier && characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
                log("Central/PeerDelegate: Write resp for unexpected char/peripheral (not chunked). Char: \(String(characteristic.uuid.uuidString.prefix(8))) on \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return
            }
            if let err = error {
                log("Central/PeerDelegate: Error WRITING (single) our card to peer \(String(describing: peripheral.name)): \(err.localizedDescription)", level: .error)
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Write local card to peer fail: \(err.localizedDescription)")) }
            } else {
                log("Central/PeerDelegate: Successfully WROTE (single) our card to peer \(String(describing: peripheral.name)).")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connectingOrConnectedPeer?.identifier == peripheral.identifier else {
            log("Central/PeerDelegate: Value update from unexpected peripheral \(String(peripheral.identifier.uuidString.prefix(8))). Ignored.", level: .warning); return }
        
        let bufferKey = PeripheralCharacteristicPair(peripheralID: peripheral.identifier, characteristicID: characteristic.uuid)
        
        if characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID {
            if let err = error {
                log("Central/PeerDelegate: Error char VALUE UPDATE \(String(characteristic.uuid.uuidString.prefix(8))): \(err.localizedDescription)", level: .error)
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.characteristicOperationFailed("Receive value peer char fail: \(err.localizedDescription)")) }
                incomingDataBuffers[bufferKey] = nil;
                return
            }
            guard let newDataChunk = characteristic.value else {
                log("Central/PeerDelegate: NIL data CardData from \(String(peripheral.identifier.uuidString.prefix(8))).", level: .warning); return }
            
            log("Central/PeerDelegate: CHUNK (\(newDataChunk.count) bytes) for \(String(bufferKey.characteristicID.uuidString.prefix(8))) from \(String(bufferKey.peripheralID.uuidString.prefix(8))).")
            
            var currentBuffer = incomingDataBuffers[bufferKey, default: Data()]
            currentBuffer.append(newDataChunk)
            incomingDataBuffers[bufferKey] = currentBuffer
            log("Central/PeerDelegate: Accumulated buffer for \(String(bufferKey.peripheralID.uuidString.prefix(8))) is now \(currentBuffer.count) bytes.")

            do {
                let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: currentBuffer)
                log("Central/PeerDelegate: DECODED card from '\(receivedCard.displayName)'. Size: \(currentBuffer.count). Drawing: \(receivedCard.drawingData != nil).")
                let rssi = peerRSSICache[peripheral.identifier]; processAndStoreReceivedCard(receivedCard, rssi: rssi)
                incomingDataBuffers[bufferKey] = nil
                
                if currentChunkedWrite == nil {
                    log("Central/PeerDelegate: Card exchange complete (received theirs, already sent ours or not sending). Disconnecting '\(peripheral.name ?? "")'.")
                    centralManager.cancelPeripheralConnection(peripheral);
                } else {
                    log("Central/PeerDelegate: Received their card, but still sending ours. Waiting for our send to complete.")
                }

            } catch let decodingError as DecodingError {
                 switch decodingError {
                 case .dataCorrupted(let context):
                     log("Central/PeerDelegate: Data CORRUPTED \(String(bufferKey.peripheralID.uuidString.prefix(8))). Buffer: \(currentBuffer.count). Context: \(context.debugDescription). Path: \(context.codingPath)", level: .error); log("Central/PeerDelegate: Snippet: \(String(data: currentBuffer.prefix(500), encoding: .utf8) ?? "Non-UTF8")")
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Data corrupted: \(context.debugDescription)")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 case .keyNotFound(let key, let context):
                     log("Central/PeerDelegate: Key '\(key.stringValue)' NOT FOUND \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error)
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Missing key '\(key.stringValue)'.")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 case .typeMismatch(let type, let context):
                     log("Central/PeerDelegate: Type MISMATCH '\(context.codingPath.last?.stringValue ?? "uk")' (exp \(type)) \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error)
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Type mismatch key '\(context.codingPath.last?.stringValue ?? "")': \(context.debugDescription).")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 case .valueNotFound(let type, let context):
                     log("Central/PeerDelegate: Value NOT FOUND type \(type) key '\(context.codingPath.last?.stringValue ?? "uk")' \(String(bufferKey.peripheralID.uuidString.prefix(8))). Context: \(context.debugDescription)", level: .error)
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Value not found key '\(context.codingPath.last?.stringValue ?? "")': \(context.debugDescription).")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 @unknown default:
                     log("Central/PeerDelegate: Unknown decode error \(String(bufferKey.peripheralID.uuidString.prefix(8))). Error: \(decodingError.localizedDescription)", level: .error)
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Unknown decode error: \(decodingError.localizedDescription)")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 }
                 if case .dataCorrupted = decodingError { /* Handled */ }
                 else if currentBuffer.count < 65535 {
                     log("Central/PeerDelegate: Decode fail (not dataCorrupted but specific like key/type/value not found), assume incomplete or malformed. Buffer: \(currentBuffer.count). Waiting more data for \(String(bufferKey.peripheralID.uuidString.prefix(8))). This might be an issue if the sender is sending bad data.", level: .warning)
                 } else {
                     log("Central/PeerDelegate: Buffer too large (\(currentBuffer.count)) and still fail decode with non-corrupt error. Giving up \(String(bufferKey.peripheralID.uuidString.prefix(8))).", level: .error)
                     DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Buffer limit exceeded decoding.")) }
                     incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
                 }
            } catch {
                log("Central/PeerDelegate: GENERIC UNEXPECTED DECODE ERROR \(String(bufferKey.peripheralID.uuidString.prefix(8))). Buffer: \(currentBuffer.count). Error: \(error.localizedDescription)", level: .error)
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Generic error decode peer card: \(error.localizedDescription)")) }
                incomingDataBuffers[bufferKey] = nil; centralManager.cancelPeripheralConnection(peripheral);
            }
        } else {
            log("Central/PeerDelegate: Updated value for unexpected characteristic: \(String(characteristic.uuid.uuidString.prefix(8))) from \(String(peripheral.identifier.uuidString.prefix(8)))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard connectingOrConnectedPeer?.identifier == peripheral.identifier else { return } // // only care about current peer
        if let err = error { log("Central/PeerDelegate: Error reading RSSI for '\(peripheral.name ?? "")': \(err.localizedDescription)", level: .warning); return }
        log("Central/PeerDelegate: Updated RSSI for '\(peripheral.name ?? "")' to \(RSSI.intValue).")
        peerRSSICache[peripheral.identifier] = RSSI
    }

    // MARK: - CBPeripheralManagerDelegate
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        log("blemanager: peripheralmanagerdidupdatestate FIRED! state: \(manager.state.rawValue)") // <--- new log
        DispatchQueue.main.async { self.delegate?.bleManagerDidUpdateState(bluetoothState: manager.state) }
        switch manager.state {
        case .poweredOn: log("Peripheral Manager: Bluetooth ON."); setupServiceAndStartAdvertising()
        case .poweredOff:
            log("Peripheral Manager: Bluetooth OFF.", level: .warning)
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT Off (Peripheral)"))
            }
            ongoingNotificationSends.removeAll()
        case .unauthorized:
            log("Peripheral Manager: BT unauthorized.", level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.bluetoothUnavailable("BT permissions not granted peripheral.")) }
        case .resetting:
            log("Peripheral Manager: BT resetting.", level: .warning)
            ongoingNotificationSends.removeAll()
        default: log("Peripheral Manager: State changed to \(manager.state.rawValue)", level: .info)
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Error adding service \(String(service.uuid.uuidString.prefix(8))): \(err.localizedDescription)", level: .error)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.serviceSetupFailed("Fail add BLE svc: \(err.localizedDescription)")) }
            return
        }
        log("Peripheral/MgrDelegate: Service \(String(service.uuid.uuidString.prefix(8))) added. Attempting start advertising...")
        actuallyStartAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ manager: CBPeripheralManager, error: Error?) {
        if let err = error {
            log("Peripheral/MgrDelegate: Fail start advertising: \(err.localizedDescription)", level: .error)
            DispatchQueue.main.async {
                self.isAdvertising = false
                self.delegate?.bleManagerDidEncounterError(.advertisingFailed("Fail start advertising: \(err.localizedDescription)"))
            }
            return
        }
        log("Peripheral/MgrDelegate: STARTED ADVERTISING StreetPass service.")
        DispatchQueue.main.async { self.isAdvertising = true }
        if let char = self.encounterCardMutableCharacteristic {
            do {
                let cardData = try jsonEncoder.encode(self.localUserCard)
                char.value = cardData
                log("Peripheral/MgrDelegate: Set initial char value on ad start. Size: \(cardData.count).")
            }
            catch { log("Peripheral/MgrDelegate: Error encode card for initial char value: \(error.localizedDescription)", level: .error) }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let centralIDPart = String(request.central.identifier.uuidString.prefix(8))
        log("Peripheral/MgrDelegate: Read Request Char UUID \(String(request.characteristic.uuid.uuidString.prefix(8))) from Central \(centralIDPart). Offset: \(request.offset). Central Max Update: \(request.central.maximumUpdateValueLength)")
        
        guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Peripheral/MgrDelegate: Read req UNKNOWN char (\(request.characteristic.uuid.uuidString)). Responding 'AttributeNotFound'.", level: .warning)
            manager.respond(to: request, withResult: .attributeNotFound); return
        }
        
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let fullCardData = try jsonEncoder.encode(cardToSend)
            log("Peripheral/MgrDelegate: Total card data size for read: \(fullCardData.count) bytes for Central \(centralIDPart).")

            if request.offset >= fullCardData.count {
                if request.offset > fullCardData.count {
                    manager.respond(to: request, withResult: .invalidOffset); return
                }
            }
            
            if let chunkToSend = fullCardData.subdataIfAppropriate(offset: request.offset, maxLength: request.central.maximumUpdateValueLength) {
                 request.value = chunkToSend
                 log("Peripheral/MgrDelegate: Responding Central \(centralIDPart) with \(chunkToSend.count) bytes (offset \(request.offset)). Success.")
                 manager.respond(to: request, withResult: .success)
            } else {
                log("Peripheral/MgrDelegate: Subdata generation failed for read request. Offset: \(request.offset), MaxLength: \(request.central.maximumUpdateValueLength). Responding InvalidOffset.", level: .error)
                manager.respond(to: request, withResult: .invalidOffset)
            }

        } catch {
            log("Peripheral/MgrDelegate: Error encoding local card for read response: \(error.localizedDescription)", level: .error)
            manager.respond(to: request, withResult: .unlikelyError)
            DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataSerializationError("Encode card read response fail: \(error.localizedDescription)")) }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            let centralID = request.central.identifier
            let centralIDPart = String(centralID.uuidString.prefix(8))
            log("Peripheral/MgrDelegate: Write Request Char UUID \(String(request.characteristic.uuid.uuidString.prefix(8))) from Central \(centralIDPart). Length: \(request.value?.count ?? 0). Offset: \(request.offset)")

            guard request.characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
                log("Peripheral/MgrDelegate: Write UNKNOWN char from \(centralIDPart). Respond 'AttributeNotFound'.", level: .warning)
                manager.respond(to: request, withResult: .attributeNotFound); continue
            }
            guard let dataChunk = request.value else {
                log("Peripheral/MgrDelegate: Write EMPTY data from \(centralIDPart). Respond 'InvalidAttributeValueLength'.", level: .warning)
                manager.respond(to: request, withResult: .invalidAttributeValueLength); continue
            }

            var currentBuffer = incomingWriteBuffers[centralID, default: Data()]
            
            if request.offset == 0 && !currentBuffer.isEmpty && dataChunk.count < currentBuffer.count {
                log("Peripheral/MgrDelegate: Write request offset 0, assuming new message from \(centralIDPart), clearing previous buffer (\(currentBuffer.count) bytes).", level: .info)
                currentBuffer = Data()
            }
            currentBuffer.append(dataChunk)
            incomingWriteBuffers[centralID] = currentBuffer
            log("Peripheral/MgrDelegate: Accumulated write buffer for \(centralIDPart) is now \(currentBuffer.count) bytes.")

            do {
                let receivedCard = try jsonDecoder.decode(EncounterCard.self, from: currentBuffer)
                log("Peripheral/MgrDelegate: DECODED card from '\(receivedCard.displayName)' (Central \(centralIDPart)) via write. Processing...", level: .info)
                processAndStoreReceivedCard(receivedCard, rssi: nil)
                incomingWriteBuffers[centralID] = nil
                manager.respond(to: request, withResult: .success)
            } catch let decodingError as DecodingError {
                log("Peripheral/MgrDelegate: DECODING card from Central \(centralIDPart) (write) FAILED (possibly incomplete): \(decodingError.localizedDescription). Current buffer size: \(currentBuffer.count)", level: .info)
                manager.respond(to: request, withResult: .success)
                if case .dataCorrupted = decodingError {
                    log("peripheral/mgrdelegate: write data corrupted from \(centralIDPart). buffer not cleared yet, waiting for more or disconnect.", level: .error)
                }

            } catch {
                log("Peripheral/MgrDelegate: GENERIC UNEXPECTED DECODE ERROR from Central \(centralIDPart) (write): \(error.localizedDescription). Size: \(currentBuffer.count)", level: .error)
                manager.respond(to: request, withResult: .unlikelyError)
                incomingWriteBuffers[centralID] = nil
                DispatchQueue.main.async { self.delegate?.bleManagerDidEncounterError(.dataDeserializationError("Decode peer card write (Central \(centralIDPart)) fail: \(error.localizedDescription)")) }
            }
        }
    }

    func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == StreetPassBLE_UUIDs.encounterCardCharacteristicUUID else {
            log("Peripheral/MgrDelegate: Central \(String(central.identifier.uuidString.prefix(8))) subscribed unexpected char \(String(characteristic.uuid.uuidString.prefix(8)))", level: .warning); return }
        let centralIDPart = String(central.identifier.uuidString.prefix(8))
        log("Peripheral/MgrDelegate: Central \(centralIDPart) SUBSCRIBED to EncounterCard char (\(String(characteristic.uuid.uuidString.prefix(8)))).")
        
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
            log("Peripheral/MgrDelegate: Added Central \(centralIDPart) to subscribed list. Count: \(subscribedCentrals.count).")
        }
        
        do {
            var cardToSend = self.localUserCard; cardToSend.lastUpdated = Date()
            let cardData = try jsonEncoder.encode(cardToSend)
            
            log("Peripheral/MgrDelegate: Initiating chunked notification send (\(cardData.count) bytes) to new subscriber \(centralIDPart).")
            ongoingNotificationSends[central.identifier] = PeripheralChunkSendOperation(
                central: central,
                characteristicUUID: characteristic.uuid,
                data: cardData
            )
            attemptToSendNextNotificationChunk(for: central.identifier)
            
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
        ongoingNotificationSends.removeValue(forKey: central.identifier)
        incomingWriteBuffers.removeValue(forKey: central.identifier)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers manager: CBPeripheralManager) {
        log("Peripheral/MgrDelegate: Peripheral manager ready to update subscribers again.")
        for centralID in ongoingNotificationSends.keys {
             log("peripheral/mgrdelegate: isreadytoupdatesubscribers - retrying send for central \(String(centralID.uuidString.prefix(8)))")
             attemptToSendNextNotificationChunk(for: centralID)
        }
    }
}

// MARK: - Data Extension
extension Data {
    func subdataIfAppropriate(offset: Int, maxLength: Int) -> Data? {
        guard offset >= 0 else { log_ble_data_helper("Invalid offset: \(offset)."); return nil }
        guard maxLength > 0 else { log_ble_data_helper("Invalid maxLength: \(maxLength). Usually means central is not ready or MTU is tiny."); return nil }
        
        if offset > self.count {
            log_ble_data_helper("Offset \(offset) > data length \(self.count). Responding InvalidOffset (nil from here).")
            return nil
        }
        if offset == self.count {
            log_ble_data_helper("Offset \(offset) == data length \(self.count). Returning empty Data for end-of-data read.")
            return Data()
        }
        
        let availableLength = self.count - offset
        let lengthToReturn = Swift.min(availableLength, maxLength)
        
        let startIndex = self.index(self.startIndex, offsetBy: offset)
        let endIndex = self.index(startIndex, offsetBy: lengthToReturn)
        log_ble_data_helper("Subdata: Total \(self.count), Offset \(offset), MaxLengthCentral \(maxLength), Available \(availableLength), Return \(lengthToReturn).")
        return self.subdata(in: startIndex..<endIndex)
    }
}

// MARK: - CBCharacteristicProperties Extension
extension CBCharacteristicProperties {
    var description: String {
        var descriptions: [String] = []
        if contains(.broadcast) { descriptions.append("broadcast") }
        if contains(.read) { descriptions.append("read") }
        if contains(.writeWithoutResponse) { descriptions.append("writeNoResp") }
        if contains(.write) { descriptions.append("write") }
        if contains(.notify) { descriptions.append("notify") }
        if contains(.indicate) { descriptions.append("indicate") }
        if contains(.authenticatedSignedWrites) { descriptions.append("authSignedWrites") }
        if contains(.extendedProperties) { descriptions.append("extProps") }
        if contains(.notifyEncryptionRequired) { descriptions.append("notifyEncReq") }
        if contains(.indicateEncryptionRequired) { descriptions.append("indicateEncReq") }
        if descriptions.isEmpty { return "none" }
        return descriptions.joined(separator: ", ")
    }
}

fileprivate func log_ble_data_helper(_ message: String) {
    print("streetpassble/datahelper: \(message)")
}
