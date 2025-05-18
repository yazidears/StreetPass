// StreetPassViewModel.swift
// The main ViewModel managing state and interactions for the StreetPass app.

import SwiftUI
import CoreBluetooth // For CBManagerState type
import Combine     // For ObservableObject and @Published

class StreetPassViewModel: ObservableObject, StreetPassBLEManagerDelegate {
    
    // The BLE manager instance
    @ObservedObject var bleManager: StreetPassBLEManager
    
    // UI State related to card editing
    @Published var isEditingMyCard: Bool = false
    @Published var cardForEditor: EncounterCard
    // UI State for feedback
    @Published var lastErrorMessage: String? = nil
    @Published var lastInfoMessage: String? = nil

    // Direct passthrough of properties from bleManager for easy UI binding
    var myCurrentCard: EncounterCard { bleManager.localUserCard }
    var recentlyEncounteredCards: [EncounterCard] { bleManager.receivedCards }
    var bleActivityLog: [String] { bleManager.activityLog }
    var isBluetoothOn: Bool { bleManager.isBluetoothPoweredOn }
    var isScanningActive: Bool { bleManager.isScanning }
    var isAdvertisingActive: Bool { bleManager.isAdvertising }
    
    init(userID: String) {
        // Step 1: Initialize bleManager
        let initialBLEManager = StreetPassBLEManager(userID: userID)
        self.bleManager = initialBLEManager

        // Step 2: Initialize cardForEditor with a default/placeholder.
        // This satisfies Swift's rule that all stored properties must be initialized
        // before `self` is used further (e.g., assigning self as delegate).
        // We will update it immediately after loading the persisted card.
        self.cardForEditor = EncounterCard(userID: userID) // Initial placeholder

        // Step 3: All properties are now initialized. We can assign `self` as delegate.
        self.bleManager.delegate = self
        
        // Step 4: Load the persisted local card (this updates `bleManager.localUserCard`).
        self.bleManager.loadLocalUserCardFromPersistence()
        
        // Step 5: Now, update `cardForEditor` to reflect the actual loaded card.
        self.cardForEditor = self.bleManager.localUserCard
        
        logViewModel("Initialized with UserID: \(userID). Editor card set from loaded/default local card.")
    }

    // MARK: - ViewModel Logging
    private func logViewModel(_ message: String) {
        bleManager.log("ViewModel: \(message)")
    }

    // MARK: - UI Actions
    func toggleStreetPassServices() {
        if isScanningActive || isAdvertisingActive {
            bleManager.stop()
            showInfoMessage("StreetPass services stopped.")
        } else {
            bleManager.start()
            showInfoMessage("StreetPass services starting...")
        }
        lastErrorMessage = nil
    }

    func clearAllEncounteredCards() {
        bleManager.clearReceivedCardsFromPersistence()
        showInfoMessage("All encountered cards have been cleared.")
    }

    func prepareCardForEditing() {
        cardForEditor = myCurrentCard // Load current actual card into the editor model
        isEditingMyCard = true
        lastErrorMessage = nil
        lastInfoMessage = nil
        logViewModel("Preparing card editor with current local card.")
    }
    
    func cancelCardEditing() {
        isEditingMyCard = false
        // No need to call refreshCardInEditor explicitly if prepareCardForEditing is used to start editing,
        // as cardForEditor would still hold the pre-edit state if not saved.
        // However, if edits were made to cardForEditor in UI and then cancelled, reverting is good.
        cardForEditor = myCurrentCard // Revert to the definitive current card
        logViewModel("Card editing cancelled.")
    }

    func saveMyEditedCard() {
        logViewModel("Attempting to save edited card...")
        if cardForEditor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorMessage("Display Name cannot be empty.")
            return
        }
        if cardForEditor.statusMessage.count > 150 {
            showErrorMessage("Status message is too long (max 150 characters).")
            return
        }
        
        cardForEditor.lastUpdated = Date()
        bleManager.updateLocalUserCard(newCard: cardForEditor)
        
        isEditingMyCard = false
        showInfoMessage("Your Encounter Card has been updated!")
        logViewModel("Local card saved successfully by ViewModel.")
    }
    
    // Not strictly needed if prepareCardForEditing is used correctly, but can be a manual reset
    func refreshCardInEditor() {
        cardForEditor = bleManager.localUserCard
        logViewModel("Editor card explicitly refreshed to match current local card.")
    }
    
    func refreshUIDataFromPull() {
        logViewModel("UI pull-to-refresh action triggered by user.")
        objectWillChange.send() // Ensure SwiftUI redraws views bound to this ViewModel
        bleManager.objectWillChange.send() // Also ensure BLE Manager's changes are picked up
    }

    // MARK: - UI Feedback Helpers
    private func showErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            self.lastErrorMessage = message
            self.lastInfoMessage = nil
        }
    }
    private func showInfoMessage(_ message: String) {
        DispatchQueue.main.async {
            self.lastInfoMessage = message
            self.lastErrorMessage = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { // Increased duration slightly
                if self.lastInfoMessage == message {
                    self.lastInfoMessage = nil
                }
            }
        }
    }

    // MARK: - StreetPassBLEManagerDelegate Conformance
    func bleManagerDidUpdateState(bluetoothState: CBManagerState) {
        logViewModel("Delegate: Bluetooth state reported as \(bluetoothState)")
        // Specific messages based on state can be helpful for user feedback.
        switch bluetoothState {
        case .poweredOff:
            showErrorMessage("Bluetooth is currently powered off.")
        case .unauthorized:
            showErrorMessage("StreetPass needs Bluetooth permission. Please enable it in Settings.")
        case .unsupported:
            showErrorMessage("This device doesn't support Bluetooth Low Energy features required by StreetPass.")
        case .poweredOn:
            // Clear any previous BT error messages when it's powered on
            if lastErrorMessage?.contains("Bluetooth") == true { lastErrorMessage = nil }
            showInfoMessage("Bluetooth is On. StreetPass is active or ready.")
        default:
            // For resetting or unknown states, a generic message might be okay, or no message.
            break
        }
    }

    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?) {
        logViewModel("Delegate: New card received from '\(card.displayName)'. RSSI: \(rssi?.stringValue ?? "N/A")")
        showInfoMessage("New Encounter Card from \(card.displayName)!")
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    func bleManagerDidUpdateLog(_ message: String) {
        // Logs are directly available via `bleManager.activityLog`.
        // This delegate is not strictly needed for UI update if binding directly.
    }

    func bleManagerDidEncounterError(_ error: StreetPassBLEError) {
        logViewModel("Delegate: Error from BLE Manager - \(error.localizedDescription)")
        showErrorMessage(error.localizedDescription)
    }
}
