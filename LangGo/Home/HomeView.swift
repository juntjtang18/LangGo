// LangGo/Home/HomeView.swift

import SwiftUI
import AVKit

private struct VisibleCardPreferenceKey: PreferenceKey {
    struct CardInfo: Equatable {
        let id: String
        let frame: CGRect
    }
    typealias Value = [CardInfo]
    static var defaultValue: Value = []
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.append(contentsOf: nextValue())
    }
}

struct HomeView: View {
    @Environment(\.theme) var theme: Theme
    @Binding var selectedTab: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Welcome
                Text("Welcome back!")
                    .font(.largeTitle.bold())
                    .foregroundColor(theme.text)
                Text("What would you like to practice today?")
                    .foregroundColor(theme.text.opacity(0.7))

                // 1×4 full-width feature list
                VStack(spacing: 12) {
                    FeatureRowCard(
                        icon: "square.stack.3d.up.fill",
                        title: "Vocabulary Notebook",
                        subtitle: "Manage your words, revise and improve.",
                        buttonTitle: "Go to Notebook",
                        action: { selectedTab = 1 }
                    )
                    FeatureRowCard(
                        icon: "rectangle.and.pencil.and.ellipsis",
                        title: "Interactive Lessons",
                        subtitle: "Engage with LangGo interactive learning.",
                        buttonTitle: "Start Learning",
                        action: { selectedTab = 2 }
                    )
                    FeatureRowCard(
                        icon: "book.fill",
                        title: "Stories",
                        subtitle: "Read stories, improve language naturally.",
                        buttonTitle: "Browse Stories",
                        action: { selectedTab = 3 }
                    )
                    FeatureRowCard(
                        icon: "captions.bubble.fill",
                        title: "Smart Translation",
                        subtitle: "Instant translations to support speaking.",
                        buttonTitle: "Start Chatting",
                        action: { selectedTab = 4 }
                    )
                }

                // Explore by course (chips)
                Text("Explore by Course")
                    .homeStyle(.sectionHeader)
                    .padding(.top, 8)
                ChipWrap(chips: ["Basic English", "IELTS English", "Business English", "Travel English", "Academic Writing"])

                // Daily recommendations
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily recommendations")
                        .homeStyle(.sectionHeader)
                        .padding(.top, 8)
                    RecommendationRow(title: "Today’s Vocabulary Review", detail: "16 cards due")
                    RecommendationRow(title: "Recommended Story", detail: "A Blackjack Bargainer")
                    RecommendationRow(title: "Conversation Topic", detail: "Common Courtesy Phrases")
                }
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
    }
}

private struct FeatureRowCard: View {
    @Environment(\.theme) var theme: Theme
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String    // kept for API compatibility (not shown in UI)
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Upper: icon + feature name + CTA ────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(theme.accent.opacity(0.12))
                    )

                // Feature name
                Text(title)
                    .font(.headline)
                    .foregroundColor(theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                // Circular CTA button
                Button(action: action) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(theme.text)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(theme.surface.opacity(0.95))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        .accessibilityLabel("Open \(title)")
                }
                .buttonStyle(.plain)
            }

            // ── Lower: description ──────────────────────────────────────────────
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(theme.text.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.surface)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Entire card is also tappable (same as CTA)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

private struct FeatureGrid<Content: View>: View {
    @Environment(\.theme) var theme: Theme
    @ViewBuilder var content: Content

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) { content }
            .padding(1)
    }
}

private struct FeatureCard: View {
    @Environment(\.theme) var theme: Theme
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(theme.accent)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent.opacity(0.12)))

            Text(title)
                .font(.headline)
                .foregroundColor(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(theme.text.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: action) {
                HStack {
                    Text(buttonTitle)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.bold())
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.surface.opacity(0.8)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

private struct ChipWrap: View {
    @Environment(\.theme) var theme: Theme
    let chips: [String]
    var body: some View {
        // simple wrap using flow layout
        FlexibleView(
            availableWidth: UIScreen.main.bounds.width - 32,
            data: chips,
            spacing: 8,
            alignment: .leading
        ) { text in
            Text(text)
                .font(.footnote.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(theme.surface))
        }
    }
}

private struct RecommendationRow: View {
    @Environment(\.theme) var theme: Theme
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundColor(theme.text)
            Spacer()
            Text(detail).foregroundColor(theme.text.opacity(0.7))
        }
        .padding(.vertical, 6)
    }
}

// Simple flexible/wrap layout
private struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let availableWidth: CGFloat
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content

    @State private var elementsSize: [Data.Element: CGSize] = [:]

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(computeRows(), id: \.self) { rowElements in
                HStack(spacing: spacing) {
                    ForEach(rowElements, id: \.self) { element in
                        content(element)
                            .fixedSize()
                            .readSize { size in elementsSize[element] = size }
                    }
                }
            }
        }
    }

    private func computeRows() -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0
        for element in data {
            let elementSize = elementsSize[element, default: CGSize(width: availableWidth, height: 1)]
            if currentRowWidth + elementSize.width + spacing > availableWidth {
                rows.append([element])
                currentRowWidth = elementSize.width + spacing
            } else {
                rows[rows.count - 1].append(element)
                currentRowWidth += elementSize.width + spacing
            }
        }
        return rows
    }
}

// ViewSize reader helper
private extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
