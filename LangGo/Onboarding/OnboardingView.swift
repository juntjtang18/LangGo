import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // State to hold the collected data
    @State private var proficiency: String = "I'm just starting"
    @State private var remindersEnabled: Bool = false
    
    @State private var currentStep = 0
    
    // Get the service and user ID
    private let strapiService = DataServices.shared.strapiService
    private let userId = UserDefaults.standard.integer(forKey: "userId")

    var body: some View {
        VStack {
            switch currentStep {
            case 0:
                LanguageSelectionView(onContinue: { nextStep() })
            case 1:
                ProficiencyView(selection: $proficiency, onContinue: { nextStep() })
            case 2:
                ReviewReminderView(onContinue: { enabled in
                    self.remindersEnabled = enabled
                    nextStep()
                })
            case 3:
                FeatureShowcaseView(onComplete: {
                    Task {
                        await saveOnboardingData()
                        hasCompletedOnboarding = true
                    }
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
    
    private func saveOnboardingData() async {
        guard userId != 0 else {
            print("Onboarding Error: User ID not found.")
            return
        }
        
        do {
            try await strapiService.updateUserProfile(
                userId: userId,
                proficiency: proficiency,
                remindersEnabled: remindersEnabled
            )
        } catch {
            print("Failed to save onboarding data: \(error.localizedDescription)")
        }
    }
}
