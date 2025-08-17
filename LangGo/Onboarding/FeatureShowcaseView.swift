//
//  FeatureShowcaseView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/13.
//


import SwiftUI

struct FeatureShowcaseView: View {
    var onComplete: () -> Void

    @State private var page = 0
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                FeaturePageView(
                    imageName: "sparkles",
                    title: "Scientific Vocabulary Notebook",
                    description: "Tracks memory level for each word and schedules optimal reviews to strengthen retention and minimize effort."
                )
                .tag(0)

                FeaturePageView(
                    imageName: "message.fill",
                    title: "AI Conversation Partner",
                    description: "Proactively starts conversations appropriate to your level and guides the discussion with relevant prompts."
                )
                .tag(1)

                FeaturePageView(
                    imageName: "book.fill",
                    title: "Contextual Reading & Listening",
                    description: "Famous short stories with tap-to-translate and integration with the Vocabulary Notebook for efficient retention."
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))

            // Bottom controls
            Group {
                if page < pageCount - 1 {
                    HStack {
                        Button("Skip") {
                            onComplete()
                        }
                        .accessibilityLabel("Skip onboarding")

                        Spacer()

                        Button("Next") {
                            withAnimation { page += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Next page")
                    }
                } else {
                    Button("LangGo to Pro, Ready to GO!") {
                        onComplete()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Finish onboarding and get started")
                }
            }
            .padding()
        }
    }
}

struct FeaturePageView: View {
    let imageName: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: imageName)
                .font(.system(size: 100))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.largeTitle)
                .bold()
            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 24)
    }
}
