// LangGo/HomeStyle.swift
import SwiftUI

/// An enum defining style cases specific to the new Home view.
enum HomeStyle {
    case greetingTitle
    case offerBanner
    case offerTitle
    case offerSubtitle
    case sectionHeader
    case practiceCard
    case practiceCardTitle
    case exploreTitle
    case exploreButton
}

/// A view modifier that applies home-screen-specific styles based on the current theme.
@MainActor
struct HomeStyleModifier: ViewModifier {
    @Environment(\.theme) var theme: Theme
    let style: HomeStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .greetingTitle:
            content
                .font(.largeTitle.bold())
                .foregroundColor(theme.text)

        case .offerBanner:
            content
                .padding()
                .background(Color.red.opacity(0.15))
                .cornerRadius(12)

        case .offerTitle:
            content
                .font(.headline.weight(.bold))
                .foregroundColor(theme.text)

        case .offerSubtitle:
            content
                .font(.subheadline)
                .foregroundColor(theme.text.opacity(0.7))

        case .sectionHeader:
            content
                .font(.title2.bold())
                .foregroundColor(theme.text)
                .padding(.vertical)

        case .practiceCard:
            content
                .padding()
                .frame(height: 320) // Width is no longer set here
                .background(theme.surface)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)

        case .practiceCardTitle:
            content
                .font(.title3.weight(.medium))
                .foregroundColor(theme.text)

        case .exploreTitle:
            content
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundColor(theme.text)

        case .exploreButton:
            content
                .font(.headline.bold())
                .foregroundColor(theme.accent)
        }
    }
}

/// A convenience extension on `View` to easily apply home styles.
extension View {
    func homeStyle(_ style: HomeStyle) -> some View {
        self.modifier(HomeStyleModifier(style: style))
    }
}
