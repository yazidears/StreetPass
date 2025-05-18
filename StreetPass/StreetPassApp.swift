//
//  StreetPassApp.swift
//  StreetPass
//
//  Created by Yazide Arsalan on 17/5/25.
//
// StreetPassApp.swift
// Main entry point and core data model for the StreetPass application.

import SwiftUI

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
    
    var lastUpdated: Date
    var cardSchemaVersion: Int = 1

    init(userID: String,
         displayName: String = "StreetPass User",
         statusMessage: String = "Ready for new encounters!",
         avatarSymbolName: String = "person.crop.circle.fill") {
        
        self.id = UUID()
        self.userID = userID
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.statusMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarSymbolName = avatarSymbolName
        self.lastUpdated = Date()
    }

    static func == (lhs: EncounterCard, rhs: EncounterCard) -> Bool {
        // Primarily for UI diffing and simple comparison.
        // The BLE manager uses a more nuanced check (isContentDifferent and lastUpdated)
        return lhs.id == rhs.id && lhs.userID == rhs.userID && lhs.lastUpdated == rhs.lastUpdated
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
            // UIDevice.identifierForVendor is okay for demo, but resets on app uninstall/reinstall.
            // A truly persistent ID across reinstalls is harder and often involves iCloud Key-Value or server.
            // For a local-only unique ID per install, UUID is good.
            let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            userDefaults.set(newID, forKey: userIDKey)
            print("StreetPassApp: Generated new UserID: \(newID)")
            return newID
        }
    }

    // Initialize the main ViewModel with the UserID.
    // @StateObject ensures it's kept alive throughout the app's lifecycle.
    @StateObject var streetPassViewModel = StreetPassViewModel(userID: getPersistentAppUserID())

    var body: some Scene {
        WindowGroup {
            StreetPass_MainView(viewModel: streetPassViewModel)
        }
    }
}
