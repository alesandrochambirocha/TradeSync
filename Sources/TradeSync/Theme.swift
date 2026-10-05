import SwiftUI

// MARK: - Design System
// Black and graphite surfaces, hairline grey edges, and a warm cream accent.
// Green and red are reserved strictly for profit and loss.

enum Theme {
    // Palette sampled from the reference: #110D0F ink, #323B51 navy,
    // #6D7585 slate, #CBCBCB silver, #F6F6F6 white.

    // Surfaces — ink with a faint navy undertone
    static let bg          = Color(hex: 0x0A0A0C)   // window background
    static let bgSidebar   = Color(hex: 0x0D0E12)   // sidebar
    static let card        = Color(hex: 0x14161C)   // card core
    static let cardShell   = Color(hex: 0x101217)   // double-bezel outer shell
    static let cardElev    = Color(hex: 0x1C1F28)   // elevated / hover
    static let inputBG     = Color(hex: 0x15171D)

    // Edges — navy-tinted hairlines, never flat grey
    static let stroke      = Color(hex: 0x272B36)
    static let strokeSoft  = Color(hex: 0x1A1D25)
    static let strokeBright = Color(hex: 0x3A4154)

    // Accent — silver / white metal, with navy & slate as support
    static let accent      = Color(hex: 0xE4E7EC)
    static let accentBright = Color(hex: 0xF6F6F6)
    static let accentDeep  = Color(hex: 0x6D7585)
    static let navy        = Color(hex: 0x323B51)
    static let slate       = Color(hex: 0x6D7585)
    static let silver      = Color(hex: 0xCBCBCB)
    static let gold        = Color(hex: 0xCBCBCB)   // legacy alias
    static let goldBright  = Color(hex: 0xF6F6F6)

    // Semantics — P&L only
    static let green       = Color(hex: 0x22C55E)
    static let red         = Color(hex: 0xEF4444)
    static let crimson     = Color(hex: 0xDC2626)

    // Text
    static let textPrimary   = Color(hex: 0xF2F3F5)
    static let textSecondary = Color(hex: 0x939AA8)
    static let textTertiary  = Color(hex: 0x5B6170)

    // Geometry
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8

    /// Ink used on top of silver fills.
    static let onAccent = Color(hex: 0x0A0A0C)

    /// Brushed-metal fill for the wordmark and primary actions.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD7DAE1), Color(hex: 0x9AA1B0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Deep navy → ink, for the app mark's tile.
    static let markGradient = LinearGradient(
        colors: [Color(hex: 0x3B4762), Color(hex: 0x222838), Color(hex: 0x111318)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let goldGradient = brandGradient

    /// Faint top-edge highlight that makes panels read as machined metal.
    static let edgeHighlight = LinearGradient(
        colors: [Color.white.opacity(0.10), Color.white.opacity(0.015), Color.clear],
        startPoint: .top, endPoint: .bottom
    )

    /// Ambient glow behind the welcome screen.
    static let ambientGlow = RadialGradient(
        colors: [Color(hex: 0x323B51).opacity(0.55), Color(hex: 0x1A1E29).opacity(0.18), Color.clear],
        center: .center, startRadius: 2, endRadius: 620
    )

    // Motion — weighted easing, never linear
    static let ease = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.55)
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }

    static func pnl(_ value: Double) -> Color {
        if value > 0.0001 { return green }
        if value < -0.0001 { return red }
        return textSecondary
    }

    // Legacy aliases
    static var purple: Color { accent }
    static var purpleLight: Color { accentBright }
    static var indigo: Color { accentDeep }
    static var blue: Color { navy }
    static var cyan: Color { silver }
    static var yellow: Color { silver }
    static var orange: Color { slate }
    static var greenDim: Color { Color(hex: 0x0A5F44) }
    static var redDim: Color { Color(hex: 0x6B2231) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - Numeric font helper (instrumentation feel)

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Card container

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.edgeHighlight, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // Outer shell: a hairline tray the core sits inside.
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius + 3, style: .continuous)
                    .fill(Theme.cardShell)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius + 3, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Reusable bits

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .tracking(0.2)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }
}

/// Small all-caps rail label, e.g. "NAVIGATION", "PERFORMANCE".
struct RailLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundColor(Theme.textTertiary)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(
                    destructive ? AnyShapeStyle(Theme.red.opacity(0.9))
                    : prominent ? AnyShapeStyle(Theme.brandGradient)
                    : AnyShapeStyle(Theme.cardElev)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(prominent || destructive ? Color.clear : Theme.stroke, lineWidth: 1)
            )
            .foregroundColor(prominent ? Theme.onAccent : (destructive ? .white : Theme.textPrimary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TagChip: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.32), lineWidth: 1))
            .foregroundColor(color)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.brandGradient)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
