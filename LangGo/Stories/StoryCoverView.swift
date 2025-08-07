import SwiftUI

struct StoryCoverView: View {
    let story: Story
    @ObservedObject var viewModel: StoryViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // --- 1. Image ---
                AsyncImage(url: story.attributes.coverImageURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 300)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(theme.secondary.opacity(0.2))
                        .frame(height: 300)
                        .overlay(Image(systemName: "book.closed").font(.largeTitle))
                }
                
                // --- Content VStack with Spacing ---
                VStack(alignment: .leading, spacing: 24) {
                    // --- 2. Title and Author ---
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.attributes.title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.primary)
                        
                        Text("by \(story.attributes.author)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    // --- 3. Brief ---
                    if let brief = story.attributes.brief {
                        Text(brief)
                            .font(.body)
                            .foregroundColor(.primary.opacity(0.8))
                    }

                    // --- 4. Button ---
                    HStack {
                        Spacer()
                        // This NavigationLink will now work correctly.
                        NavigationLink(destination: StoryReadingView(story: story, viewModel: viewModel)) {
                            HStack {
                                Text("Start Reading")
                                Image(systemName: "play.fill")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 16)
                            .background(theme.accent)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(story.attributes.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
