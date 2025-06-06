// AppTheme.swift
import SwiftUI

struct AppTheme {
    static let primaryColor = Color(red: 0.1, green: 0.25, blue: 0.7)
    static let secondaryColor = Color(red: 0.98, green: 0.82, blue: 0.22) // spAccentYellow

    static let backgroundColor = Color(UIColor.systemGroupedBackground)
    static let cardBackgroundColor = Material.thin // Used for list items, flair boxes etc.
    static let glassMaterialUltraThin = Material.ultraThinMaterial
    static let glassMaterialThin = Material.thinMaterial
    static let glassMaterialRegular = Material.regularMaterial

    static let positiveColor = Color.green
    static let negativeColor = Color.red
    static let warningColor = Color.orange
    static let infoColor = primaryColor

    static let destructiveColor = Color.pink

    static let spGradientStart = Color(red: 0.05, green: 0.5, blue: 0.55)
    static let spGradientMid = primaryColor
    static let spGradientEnd = Color(red: 0.5, green: 0.15, blue: 0.4)
    
    static let spContentBackground = Color(UIColor.systemBackground) // For text fields on dark bg etc.
    static let spPrimaryText = Color(UIColor.label)
    static let spSecondaryText = Color(UIColor.secondaryLabel)
    static let spTertiaryText = Color(UIColor.tertiaryLabel)
    static let spAccentYellow = secondaryColor
    
    static let glassBorder = Color.white.opacity(0.2)
    static let glassBorderSubtle = Color.white.opacity(0.1)

    static func userSpecificColor(for userID: String) -> Color {
        let hash = abs(userID.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.85, brightness: 0.9) // Slightly adjusted
    }
}
