import SwiftUI

struct StoryCoverView: View {
    let story: Story
    @ObservedObject var viewModel: StoryViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                
                // --- 1. Image ---
                // By wrapping the image in a GeometryReader, we can get the exact
                // width of the screen and force the image to conform to it.
                GeometryReader { geometry in
                    AsyncImage(url: story.attributes.coverImageURL) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            // Set the frame width explicitly from the geometry proxy.
                            .frame(width: geometry.size.width, height: 300)
                            .clipped() // Ensures no part of the image spills out.
                    } placeholder: {
                        Rectangle()
                            .fill(theme.secondary.opacity(0.2))
                            // Also apply the explicit width to the placeholder.
                            .frame(width: geometry.size.width, height: 300)
                            .overlay(Image(systemName: "book.closed").font(.largeTitle))
                    }
                }
                // We must also give the GeometryReader itself a fixed height so the
                // ScrollView knows how much space it occupies.
                .frame(height: 300)

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
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
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
