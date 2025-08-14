// Onboarding/ProficiencyView.swift
import SwiftUI

struct ProficiencyView: View {
    @StateObject private var viewModel = ProficiencyViewModel()
    
    @Binding var selectionId: Int
    @Binding var selectionKey: String
    var onContinue: () -> Void
    
    var body: some View {
        VStack {
            Text("How would you rate your proficiency?")
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding()

            if viewModel.isLoading {
                ProgressView()
                Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                Spacer()
            } else {
                Picker("Proficiency", selection: $selectionId) {
                    ForEach(viewModel.proficiencyLevels) { level in
                        Text(level.attributes.displayName).tag(level.id)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .onAppear {
                    if selectionId == 0, let firstLevel = viewModel.proficiencyLevels.first {
                        selectionId = firstLevel.id
                        selectionKey = firstLevel.attributes.key
                    }
                }
                .onChange(of: selectionId) { newId in
                    if let selectedLevel = viewModel.proficiencyLevels.first(where: { $0.id == newId }) {
                        selectionKey = selectedLevel.attributes.key
                    }
                }
            }

            Button("Continue", action: onContinue)
                .padding()
                .disabled(viewModel.isLoading || selectionId == 0)
        }
        .task {
            await viewModel.fetchLevels()
        }
    }
}
