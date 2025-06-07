// StreetPassViewModel.swift

import SwiftUI
import CoreBluetooth
import Combine
import UIKit

@MainActor
class StreetPassViewModel: ObservableObject, StreetPassBLEManagerDelegate {

    @Published private(set) var bleManager: StreetPassBLEManager
    private var bleManagerCancellable: AnyCancellable?
    
    @Published var isEditingMyCard: Bool = false // // old ui state, might need to rethink for new ui
    @Published var cardForEditor: EncounterCard // // used by drawing editor and old card editor
    @Published var lastErrorMessage: String? = nil
    @Published var lastInfoMessage: String? = nil
    @Published var isDrawingSheetPresented: Bool = false // // for the drawing modal
    
    // // these are mostly for the new ui to grab data
    var myCurrentCard: EncounterCard { bleManager.localUserCard }
    var recentlyEncounteredCards: [EncounterCard] { bleManager.receivedCards.sorted(by: { $0.lastUpdated > $1.lastUpdated }) }
    var bleActivityLog: [String] { bleManager.activityLog }
    var isBluetoothOn: Bool { bleManager.isBluetoothPoweredOn }
    var isScanningActive: Bool { bleManager.isScanning }
    var isAdvertisingActive: Bool { bleManager.isAdvertising }

    // // new properties for the new UI
    @Published var greetingName: String = "david" // Placeholder, should be dynamic
    @Published var newCardsCountForBanner: Int = 0 // Placeholder or specific logic needed

    init(userID: String) {
        let initialBLEManager = StreetPassBLEManager(userID: userID)
        self.bleManager = initialBLEManager
        self.cardForEditor = EncounterCard(userID: userID) // // default card for editor
        self.bleManager.delegate = self
        bindBLEManager()
        self.bleManager.loadLocalUserCardFromPersistence()
        self.cardForEditor = self.bleManager.localUserCard // // sync editor card with loaded one
        self.greetingName = self.bleManager.localUserCard.displayName.split(separator: " ").first.map(String.init) ?? "user"
        self.newCardsCountForBanner = self.bleManager.receivedCards.count // simple count for now
        logViewModel("Initialized with UserID: \(userID). Editor card set from loaded/default local card.")
    }

    private func logViewModel(_ message: String) {
        bleManager.log("ViewModel: \(message)")
    }

    private func bindBLEManager() {
        bleManagerCancellable = bleManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - UI Actions (potentially for new UI or old editor logic if kept)
    func toggleStreetPassServices() {
        if isScanningActive || isAdvertisingActive {
            bleManager.stop()
            showInfoMessage("streetpass services stopped.") // lowercase aesthetic
        } else {
            bleManager.start()
            showInfoMessage("streetpass services starting...") // lowercase aesthetic
        }
        lastErrorMessage = nil
    }

    func clearAllEncounteredCards() {
        bleManager.clearReceivedCardsFromPersistence()
        showInfoMessage("all encountered cards have been cleared.") // lowercase aesthetic
        self.newCardsCountForBanner = 0 // // update banner count
    }

    // these editing functions are tied to the old list-based editor view
    // if the new UI has a different editing flow, these might need adjustment or become helpers
    func prepareCardForEditing() {
        self.cardForEditor = self.bleManager.localUserCard
        isEditingMyCard = true // // this state might be obsolete with new ui
        lastErrorMessage = nil
        lastInfoMessage = nil
        logViewModel("Preparing card editor with a copy of the current local card.")
    }
    
    func cancelCardEditing() {
        isEditingMyCard = false // // obsolete?
        logViewModel("Card editing cancelled. Changes to editor card are discarded.")
    }

    func saveMyEditedCard() {
        logViewModel("Attempting to save edited card...")
        if cardForEditor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorMessage("display name cannot be empty."); return // lowercase aesthetic
        }
        if cardForEditor.statusMessage.count > 150 { // // hardcoded limit, ok
            showErrorMessage("status message is too long (max 150 characters)."); return // lowercase aesthetic
        }
        
        var cardToSave = self.cardForEditor
        cardToSave.lastUpdated = Date() // // always update timestamp

        if bleManager.localUserCard.isContentDifferent(from: cardToSave) {
            logViewModel("Card content changed. Generating new ID for the card and saving.")
            cardToSave.id = UUID() // // new content means new card id
        } else {
            logViewModel("Card content (text and drawing) unchanged from current. Only timestamp updated.")
            cardToSave.id = bleManager.localUserCard.id // // same content, same id
        }

        bleManager.updateLocalUserCard(newCard: cardToSave)
        
        self.cardForEditor = cardToSave // // keep editor in sync
        self.greetingName = cardToSave.displayName.split(separator: " ").first.map(String.init) ?? "user" // // update greeting name

        isEditingMyCard = false // // obsolete?
        showInfoMessage("your encounter card has been updated!") // lowercase aesthetic
        logViewModel("Local card saved. Drawing data size: \(cardToSave.drawingData?.count ?? 0) bytes.")
    }
    
    func refreshCardInEditor() { // // also for old editor
        prepareCardForEditing()
        logViewModel("Editor card explicitly refreshed to match current local card.")
    }
    
    func refreshUIDataFromPull() { // // for pull-to-refresh in old ui
        logViewModel("UI pull-to-refresh action triggered by user.")
        // // make sure all relevant @Published properties are updated if needed
        self.greetingName = self.bleManager.localUserCard.displayName.split(separator: " ").first.map(String.init) ?? "user"
        self.newCardsCountForBanner = self.bleManager.receivedCards.count
        objectWillChange.send() // // force swiftui to redraw
        bleManager.objectWillChange.send() // // and the blemanager too
    }

    // MARK: - Drawing Actions
    func openDrawingEditor() { // // this is still used for the modal
        isDrawingSheetPresented = true
    }
    
    func removeDrawingFromCard() { // // used by old editor view
        if cardForEditor.drawingData != nil {
            cardForEditor.drawingData = nil
            logViewModel("Drawing removed from card in editor. Save the card to make this change permanent.")
            showInfoMessage("drawing removed. save your card to apply changes.") // lowercase aesthetic
            objectWillChange.send() // // update ui
        }
    }

    // MARK: - UI Feedback Helpers
    // SINGLE DEFINITIONS of these methods:
    func showErrorMessage(_ message: String) { // // changed from private
        DispatchQueue.main.async {
            self.lastErrorMessage = message
            self.lastInfoMessage = nil
        }
    }

    func showInfoMessage(_ message: String) { // // changed from private
        DispatchQueue.main.async {
            self.lastInfoMessage = message
            self.lastErrorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { // // auto-dismiss
                if self.lastInfoMessage == message { // // only clear if it's the same message
                    self.lastInfoMessage = nil
                }
            }
        }
    }
    
    // // new helper for the old ui's copy to clipboard
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
        let freshManager = StreetPassBLEManager(userID: newID)
        freshManager.delegate = self
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
    // SINGLE DEFINITIONS of these delegate methods:
    func bleManagerDidUpdateState(bluetoothState: CBManagerState) {
        logViewModel("Delegate: Bluetooth state reported as \(bluetoothState.rawValue)") // Use rawValue for CBManagerState debug output
        switch bluetoothState {
        case .poweredOff: showErrorMessage("bluetooth is currently powered off.") // lowercase aesthetic
        case .unauthorized: showErrorMessage("streetpass needs bluetooth permission. please enable it in settings.") // lowercase aesthetic
        case .unsupported: showErrorMessage("this device doesn't support bluetooth low energy features required by streetpass.") // lowercase aesthetic
        case .poweredOn:
            if lastErrorMessage?.contains("bluetooth") == true { lastErrorMessage = nil } // // clear bt errors
            showInfoMessage("bluetooth is on. streetpass is active or ready.") // lowercase aesthetic
        default:
            // .unknown, .resetting
            logViewModel("Delegate: Bluetooth state is \(bluetoothState.rawValue)")
            // // what to do here? tf???
            break
        }
    }

    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?) {
        logViewModel("Delegate: New card received from '\(card.displayName)'. Drawing: \(card.drawingData != nil ? "\(card.drawingData!.count) bytes" : "No"). RSSI: \(rssi?.stringValue ?? "N/A")")
        showInfoMessage("new encounter card from \(card.displayName)!") // lowercase aesthetic
        self.newCardsCountForBanner = self.bleManager.receivedCards.count // // update banner count
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success) // // haptic feedback, nice
        #endif
    }
            
    func bleManagerDidUpdateLog(_ message: String) {
        // Logs are directly available via `bleManager.activityLog`.
        // This delegate is not strictly needed for UI update if binding directly.
        // self.objectWillChange.send() // If you need to force UI update from here
        // // so this delegate is just chillin? ok.
    }

    func bleManagerDidEncounterError(_ error: StreetPassBLEError) {
        logViewModel("Delegate: Error from BLE Manager - \(error.localizedDescription)")
        showErrorMessage(error.localizedDescription) // // show the raw error desc
    }
}
