import SwiftUI

struct StoryCoverView: View {
    let story: Story
    @ObservedObject var viewModel: StoryViewModel
    @Environment(\.theme) var theme: Theme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass // ADDED

    // State to control the presentation of the reading view
    @State private var isReadingViewPresented = false

    // ADDED: A helper function to calculate the image height dynamically.
    private func calculateImageHeight(for width: CGFloat) -> CGFloat {
        let isPad = horizontalSizeClass == .regular
        
        if isPad {
            // For iPad, a 16:9 aspect ratio provides a nice widescreen "hero image" look.
            return width * (9.0 / 16.0)
        } else {
            // For iPhone, we can use a slightly taller fixed height for a more immersive feel.
            return 400
        }
    }
    
    var body: some View {
        // MODIFIED: Wrap the entire view to get the screen width.
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let imageHeight = calculateImageHeight(for: screenWidth)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    
                    // --- 1. Image ---
                    // MODIFIED: The old GeometryReader is removed, and we use our calculated height.
                    AsyncImage(url: story.attributes.coverImageURL) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: imageHeight)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(theme.secondary.opacity(0.2))
                            .frame(width: screenWidth, height: imageHeight)
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
            .fullScreenCover(isPresented: $isReadingViewPresented) {
                NavigationStack {
                    StoryReadingView(story: story, viewModel: viewModel)
                }
            }
        }
    }
}
