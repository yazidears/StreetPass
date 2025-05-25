// StreetPassApp.swift
// Main entry point and core data model for the StreetPass application.

import SwiftUI
import UIKit // Required for UIImage to Data conversion in EncounterCard

// MARK: - Core Data Model: EncounterCard
struct EncounterCard: Identifiable, Codable, Equatable {
    var id: UUID // Unique ID for this card data instance (changes if card is edited significantly)
    let userID: String // Persistent unique ID for the user who owns this card

    var displayName: String
    var statusMessage: String
    var avatarSymbolName: String // SF Symbol name for avatar representation

    var flairField1Title: String?
    var flairField1Value: String?
    var flairField2Title: String?
    var flairField2Value: String?

    // NEW: Field for the drawing
    var drawingData: Data?

    var lastUpdated: Date
    var cardSchemaVersion: Int = 1 // Consider incrementing if drawingData is a major change

    init(userID: String,
         displayName: String = "StreetPass User",
         statusMessage: String = "Ready for new encounters!",
         avatarSymbolName: String = "person.crop.circle.fill",
         drawingData: Data? = nil) { // Added drawingData to init

        self.id = UUID()
        self.userID = userID
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.statusMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarSymbolName = avatarSymbolName
        self.drawingData = drawingData // Assign new property
        self.lastUpdated = Date()
        // If this is a significant schema change, you might update version:
        // self.cardSchemaVersion = 2
    }

    // Computed property to get UIImage from drawingData
    var drawingImage: UIImage? {
        guard let data = drawingData else { return nil }
        return UIImage(data: data)
    }

    static func == (lhs: EncounterCard, rhs: EncounterCard) -> Bool {
        // Primarily for UI diffing and simple comparison.
        // The BLE manager uses a more nuanced check (isContentDifferent and lastUpdated)
        // Note: Comparing Data directly can be slow. For `Equatable`, often ID and lastUpdated are enough.
        // If drawingData equality is important for UI updates, it's included.
        // For performance, you might exclude drawingData from Equatable if UI updates fine without it.
        return lhs.id == rhs.id &&
               lhs.userID == rhs.userID &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.drawingData == rhs.drawingData // Added drawingData comparison
    }
    
    // Helper to check if content (excluding ID and lastUpdated) is different
    func isContentDifferent(from other: EncounterCard) -> Bool {
         return self.displayName != other.displayName ||
                self.statusMessage != other.statusMessage ||
                self.avatarSymbolName != other.avatarSymbolName ||
                self.flairField1Title != other.flairField1Title ||
                self.flairField1Value != other.flairField1Value ||
                self.flairField2Title != other.flairField2Title ||
                self.flairField2Value != other.flairField2Value ||
                self.drawingData != other.drawingData || // Added drawingData check
                self.cardSchemaVersion != other.cardSchemaVersion
    }
}


// MARK: - Main Application Structure
@main
struct StreetPassApp: App {
    // Generates or retrieves a persistent User ID for this app instance.
    private static func getPersistentAppUserID() -> String {
        let userDefaults = UserDefaults.standard
        let userIDKey = "streetPass_PersistentUserID_v1" // Use a unique key for your app

        if let existingID = userDefaults.string(forKey: userIDKey) {
            print("StreetPassApp: Found existing UserID: \(existingID)")
            return existingID
        } else {
            // If no ID, generate a new one.
            let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            userDefaults.set(newID, forKey: userIDKey)
            print("StreetPassApp: Generated new UserID: \(newID)")
            return newID
        }
    }

    // Initialize the main ViewModel with the UserID.
    @StateObject var streetPassViewModel = StreetPassViewModel(userID: getPersistentAppUserID())

    var body: some Scene {
        WindowGroup {
            StreetPass_MainView(viewModel: streetPassViewModel)
        }
    }
}