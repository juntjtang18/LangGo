// LangGo/AcademyView.swift
import SwiftUI

/// A model representing a single learning module in the horizontal carousel.
struct LearningModule: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let imageName: String
}

/// The main view for the "LangGo Academy" tab.
struct AcademyView: View {
    @Environment(\.theme) var theme
    
    // The view models are passed in from the parent `LearnTabView`.
    let flashcardViewModel: FlashcardViewModel
    let learnViewModel: LearnViewModel
    
    // Binding to control the app's main tab view
    @Binding var selectedTab: Int

    // Sample data for the modules. This would eventually come from a view model.
    private let modules: [LearningModule] = [
        .init(title: "Vocabulary", description: "Add new words, start reviewing, and track your progress", imageName: "module-vocabulary"),
        .init(title: "Dental English", description: "Master specialized terminology for dental professionals.", imageName: "module-dental"),
        .init(title: "Business English", description: "Enhance your professional communication skills.", imageName: "module-placeholder")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                HeaderView()
                GreetingAndStatsView()
                ResumeButton()
                ModulesCarouselView(modules: modules, selectedTab: $selectedTab)
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - View Components

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("LangGo Academy")
                .style(.title)
            Text("Your personal language learning campus.")
                .style(.caption)
        }
    }
}

private struct CircledNumberView: View {
    let number: String
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        Text(number)
            .bold()
            .font(.caption)
            .padding(5)
            .background(theme.primary.opacity(0.2))
            .clipShape(Circle())
            .foregroundColor(theme.text)
    }
}

private struct GreetingAndStatsView: View {
    @Environment(\.theme) var theme
    @State private var username: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hi, \(username)! Ready to learn?")
                .font(.headline)
                .foregroundColor(theme.text)
            
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Recently, you learned")
                    CircledNumberView(number: "5")
                    Text("lessons, reviewed")
                    CircledNumberView(number: "123")
                }
                Text("words and remembered 56 words. You beat 54350 people, Great Job!")
            }
            .font(.subheadline)
            .foregroundColor(theme.text.opacity(0.8))
        }
        .onAppear {
            self.username = UserDefaults.standard.string(forKey: "username") ?? "User"
        }
    }
}


private struct ResumeButton: View {
    var body: some View {
        Button(action: { /* Add resume action */ }) {
            Text("Resume Learning")
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

private struct ModulesCarouselView: View {
    let modules: [LearningModule]
    @Binding var selectedTab: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Modules")
                .style(.title)
                .padding(.bottom, -8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(modules) { module in
                        let action: () -> Void = {
                            if module.title == "Vocabulary" {
                                // This action changes the binding, switching the tab
                                selectedTab = 1
                            }
                            // Other module actions can be defined here
                        }
                        ModuleCardView(module: module, action: action)
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

private struct ModuleCardView: View {
    let module: LearningModule
    let action: () -> Void
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(module.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            
            Text(module.description)
                .font(.caption)
                .foregroundColor(theme.text.opacity(0.8))
                .frame(height: 50, alignment: .top)

            Spacer()
            
            // The Start button is restored and calls the provided action
            Button(action: action) {
                Text("Start")
                    .font(.headline)
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .overlay(
                        Capsule().stroke(theme.accent, lineWidth: 1.5)
                    )
            }
        }
        .padding()
        .frame(width: 200, height: 260)
        .background(theme.secondary.opacity(0.1))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(theme.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
