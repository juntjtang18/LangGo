//
//  FeatureShowcaseView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/13.
//


import SwiftUI

struct FeatureShowcaseView: View {
    var onComplete: () -> Void

    var body: some View {
        TabView {
            FeaturePageView(
                imageName: "sparkles",
                title: "Scientific Vocabulary Notebook",
                description: "Tracks memory level for each word and schedules optimal reviews to strengthen retention and minimize effort."
            )
            FeaturePageView(
                imageName: "message.fill",
                title: "AI Conversation Partner",
                description: "Proactively starts conversations appropriate to your level and guides the discussion with relevant prompts."
            )
            FeaturePageView(
                imageName: "book.fill",
                title: "Contextual Reading & Listening",
                description: "Famous short stories with tap-to-translate and integration with the Vocabulary Notebook for efficient retention."
            )
        }
        .tabViewStyle(PageTabViewStyle())
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        .overlay(
            Button(action: onComplete) {
                Text("LangGo to Pro, Ready to GO!")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(),
            alignment: .bottom
        )
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
    }
}