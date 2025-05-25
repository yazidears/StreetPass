// StreetPassViewModel.swift
// The main ViewModel managing state and interactions for the StreetPass app.

import SwiftUI
import CoreBluetooth // For CBManagerState type
import Combine     // For ObservableObject and @Published
import UIKit       // For UIImage

class StreetPassViewModel: ObservableObject, StreetPassBLEManagerDelegate {
    
    @ObservedObject var bleManager: StreetPassBLEManager
    
    @Published var isEditingMyCard: Bool = false
    @Published var cardForEditor: EncounterCard
    @Published var lastErrorMessage: String? = nil
    @Published var lastInfoMessage: String? = nil

    // NEW: State to control drawing sheet presentation
    @Published var isDrawingSheetPresented: Bool = false
    
    var myCurrentCard: EncounterCard { bleManager.localUserCard }
    var recentlyEncounteredCards: [EncounterCard] { bleManager.receivedCards }
    var bleActivityLog: [String] { bleManager.activityLog }
    var isBluetoothOn: Bool { bleManager.isBluetoothPoweredOn }
    var isScanningActive: Bool { bleManager.isScanning }
    var isAdvertisingActive: Bool { bleManager.isAdvertising }
    
    init(userID: String) {
        let initialBLEManager = StreetPassBLEManager(userID: userID)
        self.bleManager = initialBLEManager
        self.cardForEditor = EncounterCard(userID: userID)
        self.bleManager.delegate = self
        self.bleManager.loadLocalUserCardFromPersistence()
        self.cardForEditor = self.bleManager.localUserCard
        logViewModel("Initialized with UserID: \(userID). Editor card set from loaded/default local card.")
    }

    private func logViewModel(_ message: String) {
        bleManager.log("ViewModel: \(message)")
    }

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
        // Ensure cardForEditor is a *copy* if you want "Cancel" to truly revert.
        // Or, rely on users hitting "Save" for changes to persist.
        // Current setup modifies bleManager.localUserCard via reference when cardForEditor is set directly.
        // To make 'Cancel' work perfectly, cardForEditor should be a temporary copy.
        // For now, we use the direct reference and saving makes it final.
        self.cardForEditor = self.bleManager.localUserCard // Make sure it's the latest version
        isEditingMyCard = true
        lastErrorMessage = nil
        lastInfoMessage = nil
        logViewModel("Preparing card editor with current local card.")
    }
    
    func cancelCardEditing() {
        isEditingMyCard = false
        // Revert cardForEditor to the state of myCurrentCard (which wasn't updated if no save happened)
        self.cardForEditor = self.bleManager.localUserCard
        logViewModel("Card editing cancelled.")
    }

    func saveMyEditedCard() {
        logViewModel("Attempting to save edited card...")
        if cardForEditor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showErrorMessage("Display Name cannot be empty.")
            return
        }
        if cardForEditor.statusMessage.count > 150 { // Max length from EncounterCardEditorView
            showErrorMessage("Status message is too long (max 150 characters).")
            return
        }
        
        // The drawingData on cardForEditor should already be set if DrawingEditorSheetView was used and saved.
        
        cardForEditor.lastUpdated = Date() // Update timestamp
        // If content (including drawing) has changed, generate a new ID for the card
        // This helps BLE devices recognize it as a "new" version of the card more easily.
        // This check needs to happen *before* assigning cardForEditor to bleManager.localUserCard.
        if bleManager.localUserCard.isContentDifferent(from: cardForEditor) {
            logViewModel("Card content changed. Generating new ID for the card.")
            cardForEditor.id = UUID()
        } else {
            logViewModel("Card content (text and drawing) unchanged. ID remains the same.")
            // Keep old ID if no textual or drawing changes, just a resave/timestamp update
            // However, lastUpdated itself is a change, so isContentDifferent might need refinement if ID should only change on major edits.
            // For now, lastUpdated changing also makes it "different".
        }


        bleManager.updateLocalUserCard(newCard: cardForEditor) // This saves to UserDefaults via BLE Manager
        
        isEditingMyCard = false // Close the editor section in UI
        showInfoMessage("Your Encounter Card has been updated!")
        logViewModel("Local card saved successfully by ViewModel. Drawing data size: \(cardForEditor.drawingData?.count ?? 0) bytes.")
    }
    
    func refreshCardInEditor() {
        cardForEditor = bleManager.localUserCard
        logViewModel("Editor card explicitly refreshed to match current local card.")
    }
    
    func refreshUIDataFromPull() {
        logViewModel("UI pull-to-refresh action triggered by user.")
        objectWillChange.send()
        bleManager.objectWillChange.send()
    }

    // MARK: - Drawing Action
    func openDrawingEditor() {
        // `cardForEditor.drawingData` will be passed as a binding to the sheet
        isDrawingSheetPresented = true
    }
    
    // Optional: Function to remove drawing from the card
    func removeDrawingFromCard() {
        if cardForEditor.drawingData != nil {
            cardForEditor.drawingData = nil
            logViewModel("Drawing removed from card editor. Save to make permanent.")
            // UI should update to reflect no drawing. saveMyEditedCard() will persist this.
             showInfoMessage("Drawing removed. Save your card to apply changes.")
        }
    }


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
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if self.lastInfoMessage == message {
                    self.lastInfoMessage = nil
                }
            }
        }
    }

    func bleManagerDidUpdateState(bluetoothState: CBManagerState) {
        logViewModel("Delegate: Bluetooth state reported as \(bluetoothState)")
        switch bluetoothState {
        case .poweredOff: showErrorMessage("Bluetooth is currently powered off.")
        case .unauthorized: showErrorMessage("StreetPass needs Bluetooth permission. Please enable it in Settings.")
        case .unsupported: showErrorMessage("This device doesn't support Bluetooth Low Energy features required by StreetPass.")
        case .poweredOn:
            if lastErrorMessage?.contains("Bluetooth") == true { lastErrorMessage = nil }
            showInfoMessage("Bluetooth is On. StreetPass is active or ready.")
        default: break
        }
    }

    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?) {
        logViewModel("Delegate: New card received from '\(card.displayName)'. Drawing data size: \(card.drawingData?.count ?? 0) bytes. RSSI: \(rssi?.stringValue ?? "N/A")")
        showInfoMessage("New Encounter Card from \(card.displayName)!")
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    func bleManagerDidUpdateLog(_ message: String) { /* Handled by direct binding */ }

    func bleManagerDidEncounterError(_ error: StreetPassBLEError) {
        logViewModel("Delegate: Error from BLE Manager - \(error.localizedDescription)")
        showErrorMessage(error.localizedDescription)
    }
}
