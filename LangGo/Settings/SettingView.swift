import SwiftUI

struct SettingView: View {
    /// This property wrapper reads from and writes to UserDefaults.
    @AppStorage("isRefreshModeEnabled") private var isRefreshModeEnabled = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        // A NavigationView is required for the .navigationTitle and .toolbar to work when presented as a sheet.
        NavigationView {
            Form {
                Section(header: Text("Data Options"), footer: Text("This will control data refreshing behavior in a future update.")) {
                    Toggle("REFRESH mode", isOn: $isRefreshModeEnabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
    }
}
