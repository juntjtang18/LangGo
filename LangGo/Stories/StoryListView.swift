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

    @State private var storyToPresent: Story?

    // Computed property for the dynamic section title
    private var storiesSectionTitle: String {
        if let selectedId = viewModel.selectedDifficultyID,
           let level = viewModel.difficultyLevels.first(where: { $0.id == selectedId }) {
            return level.attributes.name
        }
        return "All Stories"
    }

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
                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Section for Recommended Stories
                        Section(header: StorySectionHeader(title: "Recommended")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(viewModel.recommendedStories) { story in
                                        Button(action: { storyToPresent = story }) {
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
                                StoryRowView(row: row, onSelectStory: { story in
                                    storyToPresent = story
                                })
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
        .background(theme.background.ignoresSafeArea())
        .task {
            await viewModel.initialLoad()
        }
        .fullScreenCover(item: $storyToPresent) { story in
            NavigationStack {
                StoryReadingView(story: story, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Subviews

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
            imageSection(height: 120)
            textSection(height: 130, briefLineLimit: 1)
        }
        .frame(width: 250)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
    
    private func imageSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: story.attributes.coverImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(theme.secondary.opacity(0.2))
                    Image(systemName: "book.closed").font(.largeTitle).foregroundColor(theme.text.opacity(0.5))
                }
            }
            .frame(height: height)
            .clipped()

            LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.8)]), startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(story.attributes.difficultyName.uppercased()).storyStyle(.cardSubtitle)
                Text(story.attributes.title).storyStyle(.cardTitle)
            }.padding()
        }
    }
    
    private func textSection(height: CGFloat, briefLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(story.attributes.author).storyStyle(.cardAuthor).lineLimit(1)
            Text(story.attributes.brief ?? "No brief available.").storyStyle(.cardBrief).lineLimit(briefLineLimit)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                HStack {
                    Image(systemName: "play.fill"); Text("Read")
                }.storyStyle(.readButton)
            }
        }
        .padding()
        .frame(height: height)
        .background(cardGradient)
    }
}


struct StoryRowView: View {
    let row: StoryRow
    let onSelectStory: (Story) -> Void
    
    var body: some View {
        switch row.style {
        case .full:
            if let story = row.stories.first {
                Button(action: { onSelectStory(story) }) {
                    StoryCardView(story: story, style: .full)
                }
                .buttonStyle(PlainButtonStyle())
            }
        case .landscape:
            if let story = row.stories.first {
                Button(action: { onSelectStory(story) }) {
                    StoryCardView(story: story, style: .landscape)
                }
                .buttonStyle(PlainButtonStyle())
            }
        case .half:
            HStack(spacing: 16) {
                if let story1 = row.stories[safe: 0] {
                    Button(action: { onSelectStory(story1) }) {
                        StoryCardView(story: story1, style: .half)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                if let story2 = row.stories[safe: 1] {
                    Button(action: { onSelectStory(story2) }) {
                        StoryCardView(story: story2, style: .half)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Spacer()
                }
            }
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
        switch style {
        case .full:
            fullWidthCard
        case .landscape:
            landscapeCard
        case .half:
            halfWidthCard
        }
    }

    private var fullWidthCard: some View {
        VStack(spacing: 0) {
            imageSection(height: 210)
            textSection(height: 140, briefLineLimit: 2)
        }
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }

    private var halfWidthCard: some View {
        VStack(spacing: 0) {
            imageSection(height: 120)
            textSection(height: 130, briefLineLimit: 1)
        }
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
    
    private var landscapeCard: some View {
        HStack(spacing: 0) {
            imageSection(height: 150)
            textSection(height: 150, briefLineLimit: 2)
        }
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
    
    private func imageSection(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: story.attributes.coverImageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(theme.secondary.opacity(0.2))
                    Image(systemName: "book.closed").font(.largeTitle).foregroundColor(theme.text.opacity(0.5))
                }
            }
            .frame(height: height)
            .clipped()

            LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.8)]), startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(story.attributes.difficultyName.uppercased()).storyStyle(.cardSubtitle)
                Text(story.attributes.title).storyStyle(.cardTitle)
            }.padding()
        }
    }
    
    private func textSection(height: CGFloat, briefLineLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(story.attributes.author).storyStyle(.cardAuthor).lineLimit(1)
            Text(story.attributes.brief ?? "No brief available.").storyStyle(.cardBrief).lineLimit(briefLineLimit)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                HStack {
                    Image(systemName: "play.fill"); Text("Read")
                }.storyStyle(.readButton)
            }
        }
        .padding()
        .frame(height: height)
        .background(cardGradient)
    }
}
