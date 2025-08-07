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
                    // --- 2. Title ---
                    Text(story.attributes.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.primary)

                    // --- 3. Author and Button Row ---
                    HStack(alignment: .center) {
                        Text("by \(story.attributes.author)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Spacer()

                        NavigationLink(destination: StoryReadingView(story: story, viewModel: viewModel)) {
                            HStack {
                                Text("Start Reading")
                                Image(systemName: "play.fill")
                            }
                            .font(.subheadline) // Smaller font
                            .foregroundColor(.white)
                            .padding(.horizontal, 20) // Reduced padding
                            .padding(.vertical, 12)   // Reduced padding
                            .background(theme.accent)
                            .clipShape(Capsule())
                        }
                    }

                    // --- 4. Brief ---
                    if let brief = story.attributes.brief {
                        Text(brief)
                            .font(.body)
                            .foregroundColor(.primary.opacity(0.8))
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
