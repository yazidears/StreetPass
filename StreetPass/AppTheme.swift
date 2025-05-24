// AppTheme.swift
// Defines a simple color theme for the StreetPass application.

import SwiftUI

struct AppTheme {
    static let primaryColor = Color.blue // Or your preferred main accent color
    static let secondaryColor = Color.orange // Or a complementary accent
    
    static let backgroundColor = Color(UIColor.systemGroupedBackground) // Adapts to light/dark mode
    static let cardBackgroundColor = Material.thin // Modern card background

    static let positiveColor = Color.green
    static let negativeColor = Color.red
    static let warningColor = Color.orange
    static let infoColor = Color.blue

    static let destructiveColor = Color.pink // For destructive actions like stop, delete

    static func userSpecificColor(for userID: String) -> Color {
        let hash = abs(userID.hashValue)
        let hue = Double(hash % 360) / 360.0
        // Use slightly more vibrant saturation and brightness for user colors
        return Color(hue: hue, saturation: 0.75, brightness: 0.8)
    }
}