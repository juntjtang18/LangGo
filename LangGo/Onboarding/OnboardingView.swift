// Onboarding/OnboardingView.swift
import SwiftUI

struct OnboardingView: View {
    var onComplete: (OnboardingData) -> Void
    
    @State private var proficiencyId: Int = 0
    @State private var proficiencyKey: String = ""
    @State private var remindersEnabled: Bool = false
    @State private var currentStep = 0
    
    var body: some View {
        VStack {
            switch currentStep {
            case 0:
                LanguageSelectionView(onContinue: { nextStep() })
            case 1:
                ProficiencyView(selectionId: $proficiencyId, selectionKey: $proficiencyKey, onContinue: { nextStep() })
            case 2:
                ReviewReminderView(onContinue: { enabled in
                    self.remindersEnabled = enabled
                    nextStep()
                })
            case 3:
                FeatureShowcaseView(onComplete: {
                    let data = OnboardingData(proficiencyKey: proficiencyKey, remindersEnabled: remindersEnabled)
                    onComplete(data)
                })
            default:
                Text("Finished Onboarding")
            }
        }
    }

    private func nextStep() {
        withAnimation {
            currentStep += 1
        }
    }
}
