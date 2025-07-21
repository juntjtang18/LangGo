//
//  StoryReadingView.swift
//  LangGo
//
//  Created by James Tang on 2025/7/20.
//


// LangGo/Stories/StoryReadingView.swift
import SwiftUI

struct StoryReadingView: View {
    let story: Story
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(story.attributes.title)
                    .font(.largeTitle).bold()
                
                Text("by \(story.attributes.author)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Divider()
                
                if let text = story.attributes.text {
                    Text(text)
                        .font(.body)
                        .lineSpacing(5)
                } else {
                    Text("Story content not available.")
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(story.attributes.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}