import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var subtitle: String? = nil
    var info: String? = nil
    var accessory: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Theme.textTertiary)
                if let info {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8.5))
                        .foregroundColor(Theme.textTertiary)
                        .help(info)
                }
                Spacer()
            }
            HStack(alignment: .center, spacing: 10) {
                Text(value)
                    .font(.mono(21, .bold))
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 0)
                if let accessory { accessory }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

// MARK: - Gauges

struct MiniGauge: View {
    let fraction: Double   // 0...1
    var color: Color = Theme.green
    var trackColor: Color = Theme.cardElev

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(trackColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(180))
            Circle()
                .trim(from: 0, to: 0.5 * max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(180))
        }
        .frame(width: 42, height: 23)
        .offset(y: 6)
        .clipped()
    }
}

struct WinRateDonut: View {
    let winRate: Double // 0-100
    var body: some View {
        ZStack {
            Circle().stroke(Theme.red.opacity(0.55), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, winRate / 100)))
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Radar chart (Edge Score)

struct RadarChart: View {
    let axes: [(label: String, value: Double)]   // value 0-100
    var gridLevels: Int = 4
    var showLabels: Bool = true

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - (showLabels ? 30 : 6)
            let count = axes.count

            ZStack {
                ForEach(1...gridLevels, id: \.self) { level in
                    polygon(center: center, radius: radius * CGFloat(level) / CGFloat(gridLevels), count: count)
                        .stroke(Theme.strokeSoft, lineWidth: 1)
                }
                ForEach(0..<count, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: point(center: center, radius: radius, index: i, count: count, fraction: 1))
                    }
                    .stroke(Theme.strokeSoft, lineWidth: 1)
                }
                valuePath(center: center, radius: radius, count: count)
                    .fill(Theme.accent.opacity(0.22))
                valuePath(center: center, radius: radius, count: count)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))
                ForEach(0..<count, id: \.self) { i in
                    let frac = CGFloat(max(0.04, min(1, axes[i].value / 100)))
                    Circle()
                        .fill(Theme.accentBright)
                        .frame(width: 4.5, height: 4.5)
                        .position(point(center: center, radius: radius, index: i, count: count, fraction: frac))
                }
                if showLabels {
                    ForEach(0..<count, id: \.self) { i in
                        let pos = point(center: center, radius: radius + 19, index: i, count: count, fraction: 1)
                        VStack(spacing: 1) {
                            Text(axes[i].label)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                            Text("\(Int(axes[i].value.rounded()))")
                                .font(.mono(8.5, .bold))
                                .foregroundColor(Theme.accent)
                        }
                        .position(pos)
                    }
                }
            }
        }
    }

    private func point(center: CGPoint, radius: CGFloat, index: Int, count: Int, fraction: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
        return CGPoint(x: center.x + cos(angle) * radius * fraction,
                       y: center.y + sin(angle) * radius * fraction)
    }

    private func polygon(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { p in
            for i in 0..<count {
                let pt = point(center: center, radius: radius, index: i, count: count, fraction: 1)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func valuePath(center: CGPoint, radius: CGFloat, count: Int) -> Path {
        Path { p in
            for i in 0..<count {
                let frac = CGFloat(max(0.04, min(1, axes[i].value / 100)))
                let pt = point(center: center, radius: radius, index: i, count: count, fraction: frac)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}

// MARK: - Score ring

struct ScoreRing: View {
    let score: Double // 0-100
    var lineWidth: CGFloat = 8
    var showCaption: Bool = true

    var body: some View {
        ZStack {
            Circle().stroke(Theme.cardElev, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.01, min(1, score / 100)))
                .stroke(
                    AngularGradient(colors: [Theme.accentDeep, Theme.accent, Theme.accentBright],
                                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(score.rounded()))")
                    .font(.mono(showCaption ? 24 : 17, .bold))
                    .foregroundColor(Theme.textPrimary)
                if showCaption {
                    Text("/ 100")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
    }
}

/// Qualitative rating band for a 0-100 score.
enum ScoreBand {
    static func label(_ score: Double) -> String {
        switch score {
        case 85...: return "ELITE"
        case 70..<85: return "GREAT"
        case 55..<70: return "SOLID"
        case 40..<55: return "MIXED"
        default: return "NEEDS WORK"
        }
    }
    static func color(_ score: Double) -> Color {
        switch score {
        case 70...: return Theme.green
        case 55..<70: return Theme.accent
        case 40..<55: return Theme.gold
        default: return Theme.red
        }
    }
}

// MARK: - P&L label

struct PnLText: View {
    let value: Double
    var font: Font = .mono(13, .semibold)
    var signed: Bool = true
    var body: some View {
        Text(signed ? Fmt.signedMoney(value) : Fmt.money(value))
            .font(font)
            .foregroundColor(Theme.pnl(value))
    }
}

// MARK: - Win streak tracker (sidebar)

struct WinStreakCard: View {
    let stats: Stats

    private var isWinning: Bool { stats.currentDayStreak > 0 }
    private var magnitude: Int { abs(stats.currentDayStreak) }
    private var accent: Color { isWinning ? Theme.gold : (stats.currentDayStreak < 0 ? Theme.red : Theme.textTertiary) }

    /// Last 12 trading days, oldest → newest, for the dot strip.
    private var recent: [DayStats] { Array(stats.days.suffix(12)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: isWinning ? "flame.fill" : "bolt.slash.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isWinning ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(accent))
                Text("WIN STREAK")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(Theme.textTertiary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(magnitude)")
                    .font(.mono(26, .bold))
                    .foregroundColor(magnitude == 0 ? Theme.textSecondary : accent)
                Text(magnitude == 1 ? "day" : "days")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                Spacer()
            }

            Text(statusLine)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)

            // Recent day strip
            HStack(spacing: 3) {
                ForEach(recent) { day in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(day.netPnL > 0.0001 ? Theme.green
                              : day.netPnL < -0.0001 ? Theme.red : Theme.textTertiary)
                        .frame(height: 16)
                        .opacity(0.9)
                        .help("\(Fmt.mediumDate.string(from: day.date)) · \(Fmt.signedMoney(day.netPnL))")
                }
                if recent.isEmpty {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.cardElev)
                        .frame(height: 16)
                }
            }

            Divider().overlay(Theme.strokeSoft)

            HStack {
                miniStat("BEST RUN", "\(stats.bestDayStreak)d", Theme.gold)
                Spacer()
                miniStat("TRADES", streakTradeText, stats.currentTradeStreak >= 0 ? Theme.green : Theme.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(isWinning ? Theme.gold.opacity(0.3) : Theme.stroke, lineWidth: 1)
        )
    }

    private var statusLine: String {
        if stats.days.isEmpty { return "No trading days logged yet" }
        if stats.currentDayStreak > 0 { return "Green days in a row — keep the process" }
        if stats.currentDayStreak < 0 { return "Reset. Smallest size, best setup only." }
        return "Flat — breakeven day"
    }

    private var streakTradeText: String {
        let n = abs(stats.currentTradeStreak)
        if n == 0 { return "—" }
        return "\(n)\(stats.currentTradeStreak > 0 ? "W" : "L")"
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.mono(11, .bold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Compact sidebar metric row

struct SidebarMetric: View {
    let label: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.mono(11, .bold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Badges

struct ResultBadge: View {
    let result: TradeResult
    var body: some View {
        let color: Color = result == .win ? Theme.green : (result == .loss ? Theme.red : Theme.textSecondary)
        Text(result.rawValue.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
            .foregroundColor(color)
    }
}

struct DirectionBadge: View {
    let direction: TradeDirection
    var body: some View {
        let color: Color = direction == .long ? Theme.green : Theme.red
        HStack(spacing: 3) {
            Image(systemName: direction == .long ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 7.5, weight: .bold))
            Text(direction.rawValue.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
        .foregroundColor(color)
    }
}

struct StarRating: View {
    @Binding var rating: Int
    var interactive = true
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: 11.5))
                    .foregroundColor(i <= rating ? Theme.gold : Theme.textTertiary)
                    .onTapGesture { if interactive { rating = (rating == i) ? 0 : i } }
            }
        }
    }
}

// MARK: - Tag editor

struct TagEditorView: View {
    @Binding var tags: [String]
    var vocabulary: [String]
    var color: Color = Theme.accent
    var placeholder: String = "Type a tag and press ⏎"
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FlowLayout(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 10, weight: .semibold))
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 6.5, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color.opacity(0.32), lineWidth: 1))
                    .foregroundColor(color)
                }
                Menu {
                    ForEach(vocabulary.filter { !tags.contains($0) }, id: \.self) { v in
                        Button(v) { tags.append(v) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.cardElev))
                        .foregroundColor(Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            TextField(placeholder, text: $custom)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.strokeSoft, lineWidth: 1))
                .onSubmit {
                    let t = custom.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !tags.contains(t) { tags.append(t) }
                    custom = ""
                }
        }
    }
}

// MARK: - Screenshot well (drop / paste / browse)

struct ScreenshotWell: View {
    @EnvironmentObject var store: TradeStore
    @Binding var screenshots: [String]
    @State private var isTargeted = false
    @State private var preview: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(screenshots, id: \.self) { name in
                            thumbnail(name)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 96)
            }
            dropZone
        }
        .sheet(item: Binding(
            get: { preview.map { ImageRef(name: $0) } },
            set: { preview = $0?.name }
        )) { ref in
            ScreenshotViewer(name: ref.name).environmentObject(store)
        }
    }

    private func thumbnail(_ name: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = store.loadScreenshot(name) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Theme.cardElev)
                        .overlay(Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(Theme.textTertiary))
                }
            }
            .frame(width: 150, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(Theme.stroke, lineWidth: 1))
            .onTapGesture { preview = name }

            Button {
                store.deleteScreenshotFile(name)
                screenshots.removeAll { $0 == name }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private var dropZone: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 14))
                .foregroundColor(isTargeted ? Theme.accent : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Drop TradingView screenshot here")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isTargeted ? Theme.accent : Theme.textSecondary)
                Text("or paste from clipboard · click to browse")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            Button("Paste") { pasteFromClipboard() }
                .buttonStyle(PillButtonStyle())
            Button("Browse…") { browse() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundColor(isTargeted ? Theme.accent : Theme.stroke)
        )
        .contentShape(Rectangle())
        .onTapGesture { browse() }
        .onDrop(of: [.fileURL, .image, .png, .jpeg], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if let name = store.saveScreenshot(fromFileAt: url) { screenshots.append(name) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    Task { @MainActor in
                        if let name = store.saveScreenshot(image) { screenshots.append(name) }
                    }
                }
            }
        }
        return handled
    }

    private func pasteFromClipboard() {
        if let name = store.screenshotFromClipboard() { screenshots.append(name) }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose chart screenshots"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let name = store.saveScreenshot(fromFileAt: url) { screenshots.append(name) }
        }
    }
}

struct ImageRef: Identifiable {
    let name: String
    var id: String { name }
}

struct ScreenshotViewer: View {
    @EnvironmentObject var store: TradeStore
    @Environment(\.dismiss) var dismiss
    let name: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chart Screenshot")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.screenshotURL(name)])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(PillButtonStyle())
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            if let img = store.loadScreenshot(name) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 1180, maxHeight: 760)
                }
            } else {
                EmptyStateView(icon: "photo", title: "Image missing",
                               message: "The screenshot file could not be found on disk.")
            }
        }
        .frame(width: 1000, height: 660)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Form building blocks

struct FormRow<Content: View>: View {
    let label: String
    var width: CGFloat = 130
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textSecondary)
                .frame(width: width, alignment: .leading)
            content
        }
    }
}

/// Vertical labelled field, used by the trade entry form.
struct Field<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(Theme.textTertiary)
                if let hint {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.textTertiary)
                        .help(hint)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InputBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func inputStyle() -> some View { modifier(InputBackground()) }
}

// MARK: - Flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
