import SwiftUI

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = AppTheme(id: "OceanBreeze")
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func theme(_ theme: Theme) -> some View {
        self.environment(\.theme, theme)
    }
}
