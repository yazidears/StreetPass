// AppTheme.swift
// Defines a simple color theme for the StreetPass application.

import SwiftUI

struct AppTheme {
    // old theme - might not be used much with new design
    static let primaryColor = Color.blue // Or your preferred main accent color
    static let secondaryColor = Color.orange // Or a complementary accent
    
    static let backgroundColor = Color(UIColor.systemGroupedBackground) // Adapts to light/dark mode
    static let cardBackgroundColor = Material.thin // Modern card background

    static let positiveColor = Color.green
    static let negativeColor = Color.red
    static let warningColor = Color.orange
    static let infoColor = Color.blue

    static let destructiveColor = Color.pink // For destructive actions like stop, delete

    // new theme colors from design image
    static let spGradientStart = Color(red: 0.05, green: 0.5, blue: 0.55) // Darker teal
    static let spGradientMid = Color(red: 0.1, green: 0.25, blue: 0.7)  // Darker blue
    static let spGradientEnd = Color(red: 0.5, green: 0.15, blue: 0.4)   // Darker purple-ish red
    
    static let spContentBackground = Color.white
    static let spPrimaryText = Color.black
    static let spSecondaryText = Color.gray
    static let spAccentYellow = Color(red: 0.98, green: 0.82, blue: 0.22) // Adjusted yellow slightly
    static let spArrowRed = Color(red: 0.7, green: 0.1, blue: 0.1)     // Adjusted dark red

    static func userSpecificColor(for userID: String) -> Color {
        let hash = abs(userID.hashValue)
        let hue = Double(hash % 360) / 360.0
        // more saturation = more cool
        return Color(hue: hue, saturation: 0.75, brightness: 0.8)
    }
}
