import SwiftUI

struct StoryListView: View {
    @ObservedObject var viewModel: StoryViewModel
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DifficultyFilterView(
                difficultyLevels: viewModel.difficultyLevels,
                selectedDifficultyID: $viewModel.selectedDifficultyID
            )
            .padding([.horizontal, .top])

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading stories...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .style(.errorText)
            } else {
                List {
                    Section {
                         // MODIFIED: Pass the viewModel back to the subview
                         RecommendedStoriesView(stories: viewModel.recommendedStories, viewModel: viewModel)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                    Section {
                        ForEach(viewModel.stories) { story in
                             NavigationLink(destination: StoryReadingView(storyId: story.id, viewModel: viewModel)) {
                                StoryRowView(story: story)
                                    .task {
                                        await viewModel.loadMoreStoriesIfNeeded(currentItem: story)
                                    }
                             }
                        }
                    }
                    .listRowSeparator(.hidden)
                    
                    if viewModel.isFetchingMore {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await viewModel.initialLoad()
        }
    }
}

// MARK: - Subviews

private struct DifficultyFilterView: View {
    let difficultyLevels: [DifficultyLevel]
    @Binding var selectedDifficultyID: Int?
    @Environment(\.theme) var theme: Theme
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(difficultyLevels) { level in
                    Button(action: {
                        selectedDifficultyID = level.id
                    }) {
                        Text(level.attributes.name)
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(selectedDifficultyID == level.id ? theme.accent.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedDifficultyID == level.id ? theme.accent : .secondary)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

private struct RecommendedStoriesView: View {
    let stories: [Story]
    // MODIFIED: The viewModel is now correctly passed in again
    @ObservedObject var viewModel: StoryViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Recommended")
                .font(.title2).bold()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(stories) { story in
                        // This NavigationLink now compiles correctly
                        NavigationLink(destination: StoryReadingView(storyId: story.id, viewModel: viewModel)) {
                             StoryCardView(story: story)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}


private struct StoryCardView: View {
    let story: Story
    @Environment(\.theme) var theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            // Top part: Image with gradient and title
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: story.attributes.coverImageURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Rectangle().fill(theme.secondary.opacity(0.2))
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundColor(theme.text.opacity(0.5))
                    }
                }
                .frame(height: 210) // Approx 3/5 of total height
                .clipped()

                // Gradient overlay for text readability
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Text content on the image
                VStack(alignment: .leading, spacing: 4) {
                    Text("OUR FAVOURITES")
                        .storyStyle(.cardSubtitle)
                    
                    Text(story.attributes.title)
                        .storyStyle(.cardTitle)
                }
                .padding()
            }

            // Bottom part: Details and action button
            VStack(alignment: .leading, spacing: 8) {
                Text("Author: \(story.attributes.author)")
                    .storyStyle(.cardAuthor)
                
                Text("Brief: \(story.attributes.brief ?? "No brief available.")")
                    .storyStyle(.cardBrief)
                
                Spacer()
                
                HStack {
                    Spacer()
                    // Styled view that looks like a button
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Read")
                    }
                    .storyStyle(.readButton)
                }
            }
            .padding()
            .frame(height: 140) // Approx 2/5 of total height
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [theme.primary, theme.accent]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .frame(width: 250, height: 350)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}


private struct StoryRowView: View {
    let story: Story
    @Environment(\.theme) var theme: Theme

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: story.attributes.coverImageURL) { image in
                image.resizable()
            } placeholder: {
                 ZStack {
                    Rectangle().fill(theme.secondary.opacity(0.2))
                    Image(systemName: "book.closed")
                        .foregroundColor(theme.text.opacity(0.5))
                }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 60, height: 60)
            .cornerRadius(8)

            VStack(alignment: .leading) {
                Text(story.attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(theme.text)
                Text(story.attributes.difficultyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()

            Button(action: { /* Favorite action */ }) {
                Image(systemName: "heart")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
