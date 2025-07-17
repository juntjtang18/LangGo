import SwiftUI

struct TierIconView: View {
    let tier: String?

    var body: some View {
        Group {
            switch tier {
            case "new", nil:
                Image(systemName: "sparkle")
                    .foregroundColor(.cyan)
            case "warmup":
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
            case "weekly":
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
            case "monthly":
                Image(systemName: "calendar.circle.fill")
                    .foregroundColor(.purple)
            case "remembered":
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            default:
                // Provides a transparent placeholder to maintain alignment
                Image(systemName: "circle")
                    .opacity(0)
            }
        }
        .font(.subheadline)
        .frame(width: 20, alignment: .center) // Ensures consistent width for all icons
    }
}
