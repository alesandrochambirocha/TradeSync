import SwiftUI

// MARK: - Brand
//
// The mark is two ascending chevrons on a machined navy tile: upward momentum,
// two elements in step. It holds up from 16pt in the Dock to 160pt on the
// welcome screen because it's pure geometry with no fine detail.

enum Brand {
    static let name = "TradeSync"
    static let slogan = "Where discipline compounds."
    static let tagline = "Every execution, measured."
}

/// A single chevron, apex centred at the top of its rect.
struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 28
    /// Draws the tile behind the glyph. Off for the large welcome lockup.
    var showTile: Bool = true

    private var corner: CGFloat { size * 0.265 }
    private var stroke: CGFloat { max(1, size * 0.085) }
    private var chevronWidth: CGFloat { size * 0.46 }
    private var chevronHeight: CGFloat { size * 0.19 }

    var body: some View {
        ZStack {
            if showTile {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Theme.markGradient)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: max(0.5, size * 0.018)
                    )
            }
            chevron(opacity: 1.0)
                .offset(y: -size * 0.105)
            chevron(opacity: 0.42)
                .offset(y: size * 0.115)
        }
        .frame(width: size, height: size)
    }

    private func chevron(opacity: Double) -> some View {
        Chevron()
            .stroke(style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            .fill(
                LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xC9CED8)],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: chevronWidth, height: chevronHeight)
            .opacity(opacity)
    }
}

/// "TRADESYNC" in brushed metal, with the tracking an Apple-style wordmark uses.
struct Wordmark: View {
    var size: CGFloat = 13
    var tracking: CGFloat = 1.8
    var weight: Font.Weight = .bold

    var body: some View {
        Text("TRADE")
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(Theme.brandGradient)
        + Text("SYNC")
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .foregroundColor(Theme.slate)
    }
}
