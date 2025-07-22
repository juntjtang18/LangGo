// LangGo/HomeView.swift
import SwiftUI

// --- NEW DATA MODEL for the main grid ---
struct ActionItem: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String
    let description: String
    let buttonText: String
    let action: () -> Void
}

/// The main view for the "LangGo" home screen, redesigned to match the mockup.
struct HomeView: View {
    @Environment(\.theme) var theme
    
    // The view models are passed in from the parent `HomeTabView`.
    let flashcardViewModel: FlashcardViewModel
    let vocabookViewModel: VocabookViewModel
    
    // Binding to control the app's main tab view
    @Binding var selectedTab: Int

    // Data for the main action grid. Actions are defined here to navigate to the correct tabs.
    private var actionItems: [ActionItem] {
        [
            .init(iconName: "book.pages", title: "Vocabulary Notebook", description: "Manage your words, revise and improve.", buttonText: "Go to Notebook", action: { selectedTab = 1 }),
            .init(iconName: "play.rectangle", title: "Interactive Lessons", description: "Engage with LangGo interactive learning.", buttonText: "Start Learning", action: { /* Placeholder action for future implementation */ }),
            .init(iconName: "book", title: "Stories", description: "Read stories, improve language naturally.", buttonText: "Browse Stories", action: { selectedTab = 3 }),
            .init(iconName: "text.bubble.left.and.text.bubble.right", title: "Smart Translation", description: "Instant translations to support speaking.", buttonText: "Start Chatting", action: { selectedTab = 2 })
        ]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // 1. Welcome Header
                WelcomeHeaderView()
                
                // 2. Main 2x2 Action Grid
                MainActionGridView(items: actionItems)
                
                // 3. Explore by Course Section
                ExploreByCourseView()
                
                // 4. Daily Recommendations Section
                DailyRecommendationsView()
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - New View Components

private struct WelcomeHeaderView: View {
    @Environment(\.theme) var theme: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back!")
                .font(.largeTitle).bold()
                .foregroundColor(theme.text)
            Text("What would you like to practice today?")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

private struct MainActionGridView: View {
    let items: [ActionItem]
    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    // Define a set of futuristic, fantasy-style gradients for the cards.
    private let gradients: [LinearGradient] = [
        LinearGradient(gradient: Gradient(colors: [Color(hex: "#4facfe"), Color(hex: "#00f2fe")]), startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(gradient: Gradient(colors: [Color(hex: "#a18cd1"), Color(hex: "#fbc2eb")]), startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(gradient: Gradient(colors: [Color(hex: "#fa709a"), Color(hex: "#fee140")]), startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(gradient: Gradient(colors: [Color(hex: "#43e97b"), Color(hex: "#38f9d7")]), startPoint: .topLeading, endPoint: .bottomTrailing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            // Use enumerated to get an index for assigning a unique gradient to each card.
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ActionCardView(item: item, gradient: gradients[index % gradients.count])
            }
        }
    }
}

private struct ActionCardView: View {
    let item: ActionItem
    let gradient: LinearGradient // Accept a gradient to use as the background.
    @Environment(\.theme) var theme: Theme

    var body: some View {
        // The entire card is now a button, which is a common pattern in the App Store.
        Button(action: item.action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.title)
                    .foregroundColor(theme.background) // Use theme background color for high contrast
                    //.shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)


                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.white) // Use theme background color
                        .bold()
                        // --- THIS IS THE CHANGE ---
                        // A shadow makes the text more readable against the gradient.
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)

                    Text(item.description)
                        .font(.caption)
                        .foregroundColor(theme.background.opacity(0.8)) // Use theme background color
                        .lineLimit(2)
                        // This prevents the text from altering the card's height.
                        .fixedSize(horizontal: false, vertical: true)
                        // A shadow makes the text more readable against the gradient.
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(height: 170) // Ensures all cards have the exact same height.
        .background(gradient) // Apply the transcendent gradient background.
        .cornerRadius(20) // Use a larger corner radius for a modern, App Store-like feel.
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4) // Add a subtle shadow for depth.
    }
}


private struct ExploreByCourseView: View {
    @Environment(\.theme) var theme: Theme
    let courses = ["Basic English", "IELTS English", "Business English"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore by Course")
                .font(.title2).bold()
                .foregroundColor(theme.text)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(courses, id: \.self) { courseName in
                        Button(action: { /* Placeholder */ }) {
                            Text(courseName)
                                .font(.subheadline).bold()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .foregroundColor(theme.text)
                                .background(theme.secondary.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
}

private struct DailyRecommendationsView: View {
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily recommendations")
                .font(.title2).bold()
                .foregroundColor(theme.text)
            
            VStack(alignment: .leading, spacing: 12) {
                RecommendationRow(text: "Today's Vocabulary Review")
                RecommendationRow(text: "Recommended Story: A Blackjack Bargainer")
                RecommendationRow(text: "Conversation Topic: Common Courtesy Phrases")
            }
            .padding()
            .background(theme.surface.opacity(0.4))
            .cornerRadius(12)
        }
    }
}

private struct RecommendationRow: View {
    @Environment(\.theme) var theme: Theme
    let text: String
    
    var body: some View {
        Button(action: { /* Placeholder for navigation */ }) {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
    }
}
