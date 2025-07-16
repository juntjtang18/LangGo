import SwiftUI

// 1. The protocol clearly defines the properties for each color role.
// This gives you the `theme.text` syntax you want.
protocol Theme {
    var id: String { get }
    var primary: Color { get }
    var secondary: Color { get }
    var accent: Color { get }
    var background: Color { get }
    var text: Color { get }
    
    // Tier-specific colors
    var tierRemembered: Color { get }
    var tierMonthly: Color { get }
    var tierWeekly: Color { get }
    var tierWarmup: Color { get }
    var tierNew: Color { get }
    
    // Weighted Progress Colors
    var progressLow: Color { get }
    var progressMedium: Color { get }
    var progressHigh: Color { get }
    var progressComplete: Color { get }
}

// 2. This is the single, generic struct that represents all your themes.
struct AppTheme: Theme {
    let id: String
    private let assetPath = "ColorSchemes/"

    // The initializer just needs the theme's name.
    init(id: String) {
        self.id = id
    }

    // 3. Each property is a computed property. It calculates the correct
    // asset name on the fly. This is both dynamic and efficient.
    var primary: Color { color(for: "Primary") }
    var secondary: Color { color(for: "Secondary") }
    var accent: Color { color(for: "Accent") }
    var background: Color { color(for: "Background") }
    var text: Color { color(for: "Text") }
    
    // 4. Tier colors are now defined here.
    // In a real app, these could also be moved to the asset catalog.
    var tierRemembered: Color { .green }
    var tierMonthly: Color { .purple }
    var tierWeekly: Color { .blue }
    var tierWarmup: Color { .orange }
    var tierNew: Color { .cyan }

    // 5. Weighted progress colors are now defined here.
    var progressLow: Color { .red }
    var progressMedium: Color { .orange }
    var progressHigh: Color { .blue }
    var progressComplete: Color { .green }


    /// A private helper to create the full asset path and fetch the color.
    private func color(for role: String) -> Color {
        // e.g., "ColorSchemes/OceanBreeze/OceanBreezePrimary"
        return Color("\(assetPath)\(id)/\(id)\(role)")
    }
}
