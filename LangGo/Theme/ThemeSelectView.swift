import SwiftUI

struct ThemeSelectView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            // The VStack provides a clear layout container for the List
            VStack {
                List {
                    // The ForEach loop is now much simpler
                    ForEach(themeManager.themes, id: \.id) { theme in
                        Button(action: {
                            // Correctly pass the whole theme object
                            themeManager.setTheme(theme)
                        }) {
                            // Use the new helper view and safely check the current theme
                            ThemeRowView(
                                theme: theme,
                                isSelected: theme.id == themeManager.currentTheme.id
                            )
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
            }
            // Use the theme from the environment for the background
            .background(themeManager.currentTheme.background.ignoresSafeArea())
            .navigationTitle("Select a Theme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(themeManager.currentTheme.accent)
                }
            }
        }
    }
}
