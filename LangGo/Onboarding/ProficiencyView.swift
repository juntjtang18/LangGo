import SwiftUI

struct ProficiencyView: View {
    @Binding var selection: String
    var onContinue: () -> Void
    
    let proficiencyLevels = ["I'm just starting", "I know some basics", "I'm conversational", "I'm fluent but want to improve more"]

    var body: some View {
        VStack {
            Text("How would you rate your proficiency?")
                .font(.largeTitle)
                .padding()

            Picker("Proficiency", selection: $selection) {
                ForEach(proficiencyLevels, id: \.self) { level in
                    Text(level)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .onAppear {
                // Ensure a default value is set
                if selection.isEmpty {
                    selection = proficiencyLevels.first ?? ""
                }
            }

            Button("Continue", action: onContinue)
                .padding()
        }
    }
}
