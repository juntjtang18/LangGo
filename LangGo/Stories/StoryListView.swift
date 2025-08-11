import SwiftUI

// A model to represent a row in our dynamic list
struct StoryRow: Identifiable, Equatable {
    static func == (lhs: StoryRow, rhs: StoryRow) -> Bool {
        lhs.id == rhs.id
    }
    let id = UUID()
    let stories: [Story]
    let style: CardStyle
}

// An enum to define our card styles
enum CardStyle {
    case full
    case half
    case landscape
}

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
                StoryListScrollView(viewModel: viewModel)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .task {
            await viewModel.initialLoad()
        }
        //.navigationDestination(for: Story.self) { story in
        //    StoryCoverView(story: story, viewModel: viewModel)
        //}
    }
}

// MARK: - Subviews
private struct StoryListScrollView: View {
    @ObservedObject var viewModel: StoryViewModel

    private var storiesSectionTitle: String {
        if let selectedId = viewModel.selectedDifficultyID,
           let level = viewModel.difficultyLevels.first(where: { $0.id == selectedId }) {
            let name = level.attributes.name
            if name == "All" {
                return "All Stories"
            } else {
                return "\(name) Stories"
            }
        }
        return "All Stories"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Section for Recommended Stories
                Section(header: StorySectionHeader(title: "Recommended")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.recommendedStories) { story in
                                NavigationLink(value: story) {
                                    RecommendedStoryCardView(story: story)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Section for All Other Stories
                Section(header: StorySectionHeader(title: storiesSectionTitle)) {
                    ForEach(viewModel.storyRows) { row in
                        StoryRowView(row: row)
                        .task {
                            if row.id == viewModel.storyRows.last?.id {
                                await viewModel.loadMoreStoriesIfNeeded(currentItem: row.stories.last)
                            }
                        }
                    }
                }
                
                if viewModel.isFetchingMore {
                    ProgressView().padding()
                }
            }
            .padding()
        }
    }
}


private struct StorySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2).bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top)
    }
}

struct RecommendedStoryCardView: View {
    let story: Story
    @Environment(\.theme) var theme: Theme
    
    private let gradientPairs: [[Color]] = [
        [Color(hex: "#6a11cb"), Color(hex: "#2575fc")],
        [Color(hex: "#f857a6"), Color(hex: "#ff5858")],
        [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
        [Color(hex: "#00c6ff"), Color(hex: "#0072ff")],
        [Color(hex: "#fc4a1a"), Color(hex: "#f7b733")],
        [Color(hex: "#4776E6"), Color(hex: "#8E54E9")]
    ]
    
    private var cardGradient: LinearGradient {
        let colors = gradientPairs[story.id % gradientPairs.count]
        return LinearGradient(gradient: Gradient(colors: colors), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            imageSection(height: 124)
                .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
            textSection(briefLineLimit: 3)
                .clipShape(RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight]))
        }
        .frame(width: 250)
        .storyCardStyle()
    }
    
    private func imageSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = story.attributes.coverImageURL {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(theme.secondary.opacity(0.2))
                    Image(systemName: "book.closed").font(.largeTitle).foregroundColor(theme.text.opacity(0.5))
                }
            }
        }
        .frame(height: height)
        .overlay(
            LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.8)]), startPoint: .center, endPoint: .bottom)
        )
        .overlay(
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(story.attributes.difficultyName.uppercased()).storyStyle(.cardSubtitle)
                Text(story.attributes.title).storyStyle(.cardTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Ensures the VStack expands
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16)) // Precise padding
        )
    }
    
    // In Stories/StoryListView.swift, inside StoryCardView

    private func textSection(briefLineLimit: Int) -> some View {
        ZStack {
            cardGradient
            
            VStack(alignment: .leading) {
                // --- Top Group: Author & Brief ---
                // This group will take the space it needs for its text.
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.attributes.author)
                        .storyStyle(.cardAuthor)
                        .lineLimit(1)
                    
                    Text(story.attributes.brief ?? "No brief available.")
                        .storyStyle(.cardBrief)
                        .lineLimit(briefLineLimit)
                        // This tells the text view to take up vertical space as needed.
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 8) // Pushes the button to the bottom.
                
                // --- Bottom Group: Button ---
                HStack {
                    Spacer() // Pushes the button to the right.
                    HStack {
                        Image(systemName: "play.fill"); Text("Read")
                    }
                    .storyStyle(.readButton)
                }
            }
            .padding()
        }
    }
}


struct StoryRowView: View {
    let row: StoryRow
    
    var body: some View {
        if let story = row.stories.first {
            NavigationLink(value: story) {
                StoryCardView(story: story, style: .full)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}


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

private struct StoryCardView: View {
    let story: Story
    let style: CardStyle
    @Environment(\.theme) var theme: Theme

    private let gradientPairs: [[Color]] = [
        [Color(hex: "#6a11cb"), Color(hex: "#2575fc")],
        [Color(hex: "#f857a6"), Color(hex: "#ff5858")],
        [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
        [Color(hex: "#00c6ff"), Color(hex: "#0072ff")],
        [Color(hex: "#fc4a1a"), Color(hex: "#f7b733")],
        [Color(hex: "#4776E6"), Color(hex: "#8E54E9")]
    ]
    
    private var cardGradient: LinearGradient {
        let colors = gradientPairs[story.id % gradientPairs.count]
        return LinearGradient(gradient: Gradient(colors: colors), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        fullWidthCard
    }

    private var fullWidthCard: some View {
        VStack(spacing: 0) {
            imageSection(height: 232)
                .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
            textSection(briefLineLimit: 3)
                .clipShape(RoundedCorner(radius: 20, corners: [.bottomLeft, .bottomRight]))
        }
        .storyCardStyle()
    }
    
    private func imageSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = story.attributes.coverImageURL {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(theme.secondary.opacity(0.2))
                    Image(systemName: "book.closed").font(.largeTitle).foregroundColor(theme.text.opacity(0.5))
                }
            }
        }
        .frame(height: height)
        .overlay(
             LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.8)]), startPoint: .center, endPoint: .bottom)
        )
        .overlay(
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(story.attributes.difficultyName.uppercased()).storyStyle(.cardSubtitle)
                Text(story.attributes.title).storyStyle(.cardTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Ensures the VStack expands
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16)) // Precise padding
        )
    }
    
    // In Stories/StoryListView.swift, inside StoryCardView

    private func textSection(briefLineLimit: Int) -> some View {
        ZStack {
            cardGradient
            
            VStack(alignment: .leading) {
                // --- Top Group: Author & Brief ---
                // This group will take the space it needs for its text.
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.attributes.author)
                        .storyStyle(.cardAuthor)
                        .lineLimit(1)
                    
                    Text(story.attributes.brief ?? "No brief available.")
                        .storyStyle(.cardBrief)
                        .lineLimit(briefLineLimit)
                        // This tells the text view to take up vertical space as needed.
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 8) // Pushes the button to the bottom.
                
                // --- Bottom Group: Button ---
                HStack {
                    Spacer() // Pushes the button to the right.
                    HStack {
                        Image(systemName: "play.fill"); Text("Read")
                    }
                    .storyStyle(.readButton)
                }
            }
            .padding()
        }
    }
}
