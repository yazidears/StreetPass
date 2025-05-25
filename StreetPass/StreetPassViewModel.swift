// StreetPassViewModel.swift

import SwiftUI
import CoreBluetooth
import Combine
import UIKit

class StreetPassViewModel: ObservableObject, StreetPassBLEManagerDelegate {
    
    @ObservedObject var bleManager: StreetPassBLEManager
    
    @Published var isEditingMyCard: Bool = false
    @Published var cardForEditor: EncounterCard
    @Published var lastErrorMessage: String? = nil
    @Published var lastInfoMessage: String? = nil
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
            showErrorMessage("Display Name cannot be empty."); return
        }
        if cardForEditor.statusMessage.count > 150 {
            showErrorMessage("Status message is too long (max 150 characters)."); return
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

        isEditingMyCard = false
        showInfoMessage("Your Encounter Card has been updated!")
        logViewModel("Local card saved. Drawing data size: \(cardToSave.drawingData?.count ?? 0) bytes.")
    }
    
    func refreshCardInEditor() {
        prepareCardForEditing()
        logViewModel("Editor card explicitly refreshed to match current local card.")
    }
    
    func refreshUIDataFromPull() {
        logViewModel("UI pull-to-refresh action triggered by user.")
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
            showInfoMessage("Drawing removed. Save your card to apply changes.")
            objectWillChange.send()
        }
    }

    // MARK: - UI Feedback Helpers
    // SINGLE DEFINITIONS of these methods:
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

    // MARK: - StreetPassBLEManagerDelegate Conformance
    // SINGLE DEFINITIONS of these delegate methods:
    func bleManagerDidUpdateState(bluetoothState: CBManagerState) {
        logViewModel("Delegate: Bluetooth state reported as \(bluetoothState.rawValue)") // Use rawValue for CBManagerState debug output
        switch bluetoothState {
        case .poweredOff: showErrorMessage("Bluetooth is currently powered off.")
        case .unauthorized: showErrorMessage("StreetPass needs Bluetooth permission. Please enable it in Settings.")
        case .unsupported: showErrorMessage("This device doesn't support Bluetooth Low Energy features required by StreetPass.")
        case .poweredOn:
            if lastErrorMessage?.contains("Bluetooth") == true { lastErrorMessage = nil }
            showInfoMessage("Bluetooth is On. StreetPass is active or ready.")
        default:
            // .unknown, .resetting
            logViewModel("Delegate: Bluetooth state is \(bluetoothState.rawValue)")
            break
        }
    }

    func bleManagerDidReceiveCard(_ card: EncounterCard, rssi: NSNumber?) {
        logViewModel("Delegate: New card received from '\(card.displayName)'. Drawing: \(card.drawingData != nil ? "\(card.drawingData!.count) bytes" : "No"). RSSI: \(rssi?.stringValue ?? "N/A")")
        showInfoMessage("New Encounter Card from \(card.displayName)!")
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
            
    func bleManagerDidUpdateLog(_ message: String) {
        // Logs are directly available via `bleManager.activityLog`.
        // This delegate is not strictly needed for UI update if binding directly.
        // self.objectWillChange.send() // If you need to force UI update from here
    }

    func bleManagerDidEncounterError(_ error: StreetPassBLEError) {
        logViewModel("Delegate: Error from BLE Manager - \(error.localizedDescription)")
        showErrorMessage(error.localizedDescription)
    }
}
