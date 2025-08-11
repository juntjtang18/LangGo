import SwiftUI

struct StoryCoverView: View {
    let story: Story
    @ObservedObject var viewModel: StoryViewModel
    @Environment(\.theme) var theme: Theme
    
    // State to control the presentation of the reading view
    @State private var isReadingViewPresented = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                
                // --- 1. Image ---
                GeometryReader { geometry in
                    AsyncImage(url: story.attributes.coverImageURL) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: 300)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(theme.secondary.opacity(0.2))
                            .frame(width: geometry.size.width, height: 300)
                            .overlay(Image(systemName: "book.closed").font(.largeTitle))
                    }
                }
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

                        // This is now a Button that toggles our state
                        Button(action: {
                            isReadingViewPresented.toggle()
                        }) {
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
        // This modifier presents the reading view over the entire screen
        .fullScreenCover(isPresented: $isReadingViewPresented) {
            // We wrap the reading view in a NavigationStack so it gets a navigation bar
            // for the title and dismiss button.
            NavigationStack {
                StoryReadingView(story: story, viewModel: viewModel)
            }
        }
    }
}
