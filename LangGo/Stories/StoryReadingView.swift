import SwiftUI

struct StoryReadingView: View {
    @State var story: Story
    @ObservedObject var viewModel: StoryViewModel
    
    @Environment(\.theme) var theme: Theme
    
    // The story content is now a simple property, pre-computed in the initializer.
    private let storyContent: [(paragraph: String, imageURL: URL?)]

    @State private var isLiked: Bool
    
    init(story: Story, viewModel: StoryViewModel) {
        self._story = State(initialValue: story)
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._isLiked = State(initialValue: (story.attributes.like_count ?? 0) > 0)

        // --- All data processing is now done here, once. ---
        let paragraphs = story.attributes.text?.split(separator: "\n").map(String.init) ?? []
        var illustrationsDict: [Int: URL] = [:]
        if let illustrationComponents = story.attributes.illustrations {
            for ill in illustrationComponents {
                if let p = ill.paragraph, let urlString = ill.media?.data?.attributes.url, let url = URL(string: urlString) {
                    // Strapi paragraph index is 1-based; convert to 0-based for array matching.
                    illustrationsDict[p - 1] = url
                }
            }
        }
        
        // Create the final content array.
        self.storyContent = paragraphs.enumerated().map { (index, text) in
            return (paragraph: text, imageURL: illustrationsDict[index])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncImage(url: story.attributes.coverImageURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 250)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(theme.secondary.opacity(0.2))
                        .frame(height: 250)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(story.attributes.title)
                        .font(.largeTitle).bold()
                    
                    Text("by \(story.attributes.author)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    // The ForEach loop is now much simpler.
                    ForEach(storyContent.indices, id: \.self) { index in
                        let content = storyContent[index]
                        
                        Text(content.paragraph)
                            .font(.body)
                            .lineSpacing(5)
                        
                        if let imageURL = content.imageURL {
                            AsyncImage(url: imageURL) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(12)
                            } placeholder: {
                                ProgressView()
                            }
                            .padding(.vertical)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(story.attributes.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isLiked.toggle()
                    Task {
                        await viewModel.toggleLike(for: story)
                    }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : nil)
                }
            }
        }
    }
}
