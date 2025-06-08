// StreetPassViewModel.swift
// this is the app's brain. it holds all the state and talks to the bluetooth stuff.

import SwiftUI
import CoreBluetooth
import Combine
import UIKit

@MainActor
class StreetPassViewModel: ObservableObject, StreetPassBLEManagerDelegate {

    // the manager is now an optional, because we're creating it *after* init.
    // this is the key to the whole damn thing.
    @Published var bleManager: StreetPassBLEManager!
    private var bleManagerCancellable: AnyCancellable?
    
    // state for all the different UI parts
    @Published var isEditingMyCard: Bool = false
    @Published var cardForEditor: EncounterCard
    @Published var lastErrorMessage: String? = nil
    @Published var lastInfoMessage: String? = nil
    @Published var isDrawingSheetPresented: Bool = false
    
    // quick shortcuts for the views to grab data
    // we have to check if the manager exists, otherwise... boom.
    var myCurrentCard: EncounterCard { bleManager?.localUserCard ?? EncounterCard(userID: self.userID) }
    var recentlyEncounteredCards: [EncounterCard] { bleManager?.receivedCards.sorted(by: { $0.lastUpdated > $1.lastUpdated }) ?? [] }
    var bleActivityLog: [String] { bleManager?.activityLog ?? [] }
    var isBluetoothOn: Bool { bleManager?.isBluetoothPoweredOn ?? false }
    var isScanningActive: Bool { bleManager?.isScanning ?? false }
    var isAdvertisingActive: Bool { bleManager?.isAdvertising ?? false }

    // more state for the pretty UI
    @Published var greetingName: String = "david"
    @Published var newCardsCountForBanner: Int = 0
    
    private let userID: String

    init(userID: String) {
        // the init is now DUMB. it does nothing but set a default value.
        // no bluetooth, no file loading, no deadlocks.
        self.userID = userID
        self.cardForEditor = EncounterCard(userID: userID)
        print("ViewModel created, but it's just chilling for now. No bluetooth code has been touched.")
    }
    // In StreetPassViewModel.swift
    func forgetUser(userID: String) {
        bleManager.forgetEncounterForUser(userID: userID)
        // You might want to refresh UI elements that depend on this, e.g., newCardsCountForBanner
        // self.newCardsCountForBanner = self.bleManager.receivedCards.count
        // objectWillChange.send() // ViewModel will update from bleManager's objectWillChange
        showInfoMessage("encounter history for user \(userID.prefix(8))... cleared.")
    }
    // THIS IS OUR NEW HERO. WE CALL THIS *AFTER* THE LOADING SCREEN IS VISIBLE.
    func setup() async {
        // if we already set up, don't do it again.
        guard self.bleManager == nil else { return }
        
        logViewModel("Ok, for real this time. The UI is stable. Activating the ViewModel and creating BLE Manager.")
        
        let initialBLEManager = StreetPassBLEManager(userID: self.userID)
        self.bleManager = initialBLEManager
        
        self.bleManager.delegate = self
        bindBLEManager()
        
        self.bleManager.loadLocalUserCardFromPersistence()
        
        // now that we have real data, update the published properties
        self.cardForEditor = self.bleManager.localUserCard
        self.greetingName = self.bleManager.localUserCard.displayName.split(separator: " ").first.map(String.init) ?? "user"
        self.newCardsCountForBanner = self.bleManager.receivedCards.count
        
        // a little delay just to be safe and let any queued UI events settle.
        try? await Task.sleep(nanoseconds: 1_000_000) // 1 millisecond
        
        logViewModel("Activation complete. All systems are go.")
    }

    private func logViewModel(_ message: String) {
        // gotta check if the manager exists before we try to use it for logging
        if bleManager != nil {
            bleManager.log("ViewModel: \(message)")
        } else {
            print("ViewModel (pre-activation): \(message)")
        }
    }

    private func bindBLEManager() {
        // just making sure the viewmodel knows what's up when the ble manager does stuff. it's like gossip.
        bleManagerCancellable = bleManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - UI Actions
    func toggleStreetPassServices() {
        if isScanningActive || isAdvertisingActive {
            bleManager.stop()
            showInfoMessage("streetpass services stopped.")
        } else {
            bleManager.start()
            showInfoMessage("streetpass services starting...")
        }
        lastErrorMessage = nil
    }

    func clearAllEncounteredCards() {
        bleManager.clearReceivedCardsFromPersistence()
        showInfoMessage("all encountered cards have been cleared.")
        self.newCardsCountForBanner = 0
    }

    func prepareCardForEditing() {
        self.cardForEditor = self.bleManager.localUserCard
        isEditingMyCard = true
        lastErrorMessage = nil
        lastInfoMessage = nil
        logViewModel("Preparing card editor with a copy of the current local card.")
    }
    
    func cancelCardEditing() {
        isEditingMyCard = false
        logViewModel("Card editing cancelled. Changes to editor card are discarded.")
    }

    func saveMyEditedCard() {
        logViewModel("Attempting to save edited card...")
        if cardForEditor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorMessage("display name cannot be empty."); return
        }
        if cardForEditor.statusMessage.count > 150 {
            showErrorMessage("status message is too long (max 150 characters)."); return
        }
        
        var cardToSave = self.cardForEditor
        cardToSave.lastUpdated = Date()

        if bleManager.localUserCard.isContentDifferent(from: cardToSave) {
            logViewModel("Card content changed. Generating new ID for the card and saving.")
            cardToSave.id = UUID()
        } else {
            logViewModel("Card content (text and drawing) unchanged from current. Only timestamp updated.")
            cardToSave.id = bleManager.localUserCard.id
        }

        bleManager.updateLocalUserCard(newCard: cardToSave)
        
        self.cardForEditor = cardToSave
        self.greetingName = cardToSave.displayName.split(separator: " ").first.map(String.init) ?? "user"

        isEditingMyCard = false
        showInfoMessage("your encounter card has been updated!")
        logViewModel("Local card saved. Drawing data size: \(cardToSave.drawingData?.count ?? 0) bytes.")
    }
    
    func refreshCardInEditor() {
        prepareCardForEditing()
        logViewModel("Editor card explicitly refreshed to match current local card.")
    }
    
    func refreshUIDataFromPull() {
        logViewModel("UI pull-to-refresh action triggered by user.")
        self.greetingName = self.bleManager.localUserCard.displayName.split(separator: " ").first.map(String.init) ?? "user"
        self.newCardsCountForBanner = self.bleManager.receivedCards.count
        objectWillChange.send()
        bleManager.objectWillChange.send()
    }

    // MARK: - Drawing Actions
    func openDrawingEditor() {
        isDrawingSheetPresented = true
    }
    
    func removeDrawingFromCard() {
        if cardForEditor.drawingData != nil {
            cardForEditor.drawingData = nil
            logViewModel("Drawing removed from card in editor. Save the card to make this change permanent.")
            showInfoMessage("drawing removed. save your card to apply changes.")
            objectWillChange.send()
        }
    }

    // MARK: - UI Feedback Helpers
    func showErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            self.lastErrorMessage = message
            self.lastInfoMessage = nil
        }
    }

    func showInfoMessage(_ message: String) {
        DispatchQueue.main.async {
            self.lastInfoMessage = message
            self.lastErrorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if self.lastInfoMessage == message {
                    self.lastInfoMessage = nil
                }
            }
        }
    }
    
    func showInfoMessageForCopyToClipboard(_ message: String) {
        showInfoMessage(message)
    }

    // MARK: - Reset & Restart Logic
    func resetAllData() {
        logViewModel("Resetting all StreetPass data and generating new user ID.")
        bleManager.stop()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "streetPass_PersistentUserID_v1")
        defaults.removeObject(forKey: "streetPass_LocalUserCard_v2")
        defaults.removeObject(forKey: "streetPass_ReceivedCards_v2")
        let newID = UUID().uuidString
        defaults.set(newID, forKey: "streetPass_PersistentUserID_v1")
        
        // create a whole new manager
        let freshManager = StreetPassBLEManager(userID: newID)
        self.bleManager = freshManager
        bindBLEManager()

        self.cardForEditor = freshManager.localUserCard
        self.greetingName = freshManager.localUserCard.displayName.split(separator: " ").first.map(String.init) ?? "user"
        self.newCardsCountForBanner = 0
        self.lastErrorMessage = nil
        self.lastInfoMessage = nil
        bleManager.start()
        objectWillChange.send()
    }

    // MARK: - StreetPassBLEManagerDelegate Conformance
    func bleManagerDidUpdateState(bluetoothState: CBManagerState) {
        logViewModel("Delegate: Bluetooth state reported as \(bluetoothState.rawValue)")
        switch bluetoothState {
        case .poweredOff: showErrorMessage("bluetooth is currently powered off.")
        case .unauthorized: showErrorMessage("streetpass needs bluetooth permission. please enable it in settings.")
        case .unsupported: showErrorMessage("this device doesn't support bluetooth low energy features required by streetpass.")
        case .poweredOn:
            if lastErrorMessage?.contains("bluetooth") == true { lastErrorMessage = nil }
            showInfoMessage("bluetooth is on. streetpass is active or ready.")
        default:
            logViewModel("Delegate: Bluetooth state is \(bluetoothState.rawValue)")
            // lol idk what to do here, so we do nothing.
            break
        }
    }

    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?) {
        logViewModel("Delegate: New card received from '\(card.displayName)'. Drawing: \(card.drawingData != nil ? "\(card.drawingData!.count) bytes" : "No"). RSSI: \(rssi?.stringValue ?? "N/A")")
        showInfoMessage("new encounter card from \(card.displayName)!")
        self.newCardsCountForBanner = self.bleManager.receivedCards.count
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success) // buzz buzz
        #endif
    }
            
    func bleManagerDidUpdateLog(_ message: String) {
        // the view can just read the log array directly, so this is just here vibing
    }

    func bleManagerDidEncounterError(_ error: StreetPassBLEError) {
        logViewModel("Delegate: Error from BLE Manager - \(error.localizedDescription)")
        showErrorMessage(error.localizedDescription)
    }
}
