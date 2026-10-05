import SwiftUI
import Charts

// MARK: - Trade Review
//
// One review page for any horizon: a week, a month, three months or a year.
// What the period produced, which confluences earned it, what tagged mistakes
// cost, whether the process held, and the takeaway you carry forward.

enum ReviewKind: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "3 Months"
    case year = "Year"
    var id: String { rawValue }

    /// "week", "month", "3 months", "year" — for phrases like "vs previous month".
    var noun: String { rawValue.lowercased() }

    var headline: String {
        switch self {
        case .week: return "Week P&L"
        case .month: return "Month P&L"
        case .quarter: return "3-Month P&L"
        case .year: return "Year P&L"
        }
    }

    /// Bar granularity for the breakdown chart.
    var chartUnit: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        case .year: return .month
        }
    }

    var chartTitle: String {
        switch self {
        case .week, .month: return "Day by Day"
        case .quarter: return "Week by Week"
        case .year: return "Month by Month"
        }
    }

    fileprivate var step: (Calendar.Component, Int) {
        switch self {
        case .week: return (.day, 7)
        case .month: return (.month, 1)
        case .quarter: return (.month, 3)
        case .year: return (.year, 1)
        }
    }
}

struct ReviewPeriod: Equatable {
    let kind: ReviewKind
    let start: Date
    let end: Date          // exclusive

    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2   // weeks run Monday–Sunday
        return cal
    }

    static func containing(_ date: Date, kind: ReviewKind) -> ReviewPeriod {
        let cal = calendar
        switch kind {
        case .week:
            let i = cal.dateInterval(of: .weekOfYear, for: date)!
            return ReviewPeriod(kind: kind, start: i.start, end: i.end)
        case .month:
            let i = cal.dateInterval(of: .month, for: date)!
            return ReviewPeriod(kind: kind, start: i.start, end: i.end)
        case .quarter:
            // Three calendar months ending with the month that contains `date`.
            let month = cal.dateInterval(of: .month, for: date)!
            let start = cal.date(byAdding: .month, value: -2, to: month.start)!
            return ReviewPeriod(kind: kind, start: start, end: month.end)
        case .year:
            let i = cal.dateInterval(of: .year, for: date)!
            return ReviewPeriod(kind: kind, start: i.start, end: i.end)
        }
    }

    func shifted(by n: Int) -> ReviewPeriod {
        let (component, size) = kind.step
        let last = end.addingTimeInterval(-1)
        let anchor = Self.calendar.date(byAdding: component, value: n * size, to: last) ?? last
        return .containing(anchor, kind: kind)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
    var isCurrent: Bool { contains(Date()) }

    var label: String {
        let last = end.addingTimeInterval(-1)
        func f(_ format: String, _ d: Date) -> String {
            let df = DateFormatter(); df.dateFormat = format; return df.string(from: d)
        }
        let sameYear = Self.calendar.component(.year, from: start) == Self.calendar.component(.year, from: last)
        switch kind {
        case .week:    return "\(f("d MMM", start)) – \(f("d MMM yyyy", last))"
        case .month:   return f("MMMM yyyy", start)
        case .quarter: return sameYear ? "\(f("MMM", start)) – \(f("MMM yyyy", last))"
                                       : "\(f("MMM yyyy", start)) – \(f("MMM yyyy", last))"
        case .year:    return f("yyyy", start)
        }
    }

    /// Where this period's takeaway is stored. Weekly keys predate the other
    /// horizons and are kept so existing notes still load.
    var notesKey: String {
        let cal = Self.calendar
        switch kind {
        case .week:
            return String(format: "week-%04d-W%02d",
                          cal.component(.yearForWeekOfYear, from: start),
                          cal.component(.weekOfYear, from: start))
        case .month:
            return String(format: "review-month-%04d-%02d",
                          cal.component(.year, from: start), cal.component(.month, from: start))
        case .quarter:
            let last = end.addingTimeInterval(-1)
            return String(format: "review-3m-%04d-%02d",
                          cal.component(.year, from: last), cal.component(.month, from: last))
        case .year:
            return String(format: "review-year-%04d", cal.component(.year, from: start))
        }
    }
}

struct ReviewView: View {
    @EnvironmentObject var store: TradeStore
    @State private var period: ReviewPeriod

    init(kind: ReviewKind = .week) {
        _period = State(initialValue: .containing(Date(), kind: kind))
    }
    @State private var notes = ""
    @State private var loadedKey = ""

    private var kind: ReviewKind { period.kind }
    private var trades: [Trade] { store.scopedTrades.filter { period.contains($0.exitTime) } }
    private var previous: [Trade] {
        let p = period.shifted(by: -1)
        return store.scopedTrades.filter { p.contains($0.exitTime) }
    }
    private var stats: Stats { Stats(trades: trades) }
    private var prevStats: Stats { Stats(trades: previous) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                if trades.isEmpty {
                    EmptyStateView(icon: "calendar.badge.clock",
                                   title: "No trades this \(kind.noun)",
                                   message: "Step back to an earlier \(kind.noun), or import your latest export. The review fills in once the period has trades.")
                        .frame(minHeight: 420)
                } else {
                    headlineRow
                    HStack(alignment: .top, spacing: 13) {
                        breakdownCard
                        comparisonCard.frame(width: 300)
                    }
                    .frame(height: 260)
                    HStack(alignment: .top, spacing: 13) {
                        whatWorkedCard
                        whatItCostCard
                    }
                    disciplineCard
                    bestWorstRow
                }
                notesCard
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header.background(Theme.bg)
        }
        .onAppear(perform: loadNotes)
    }

    // MARK: header

    private var header: some View {
        PageHeader(title: "Trade Review",
                   subtitle: period.label + (period.isCurrent ? " · in progress" : "")) {
            HStack(spacing: 10) {
                kindPicker
                HStack(spacing: 6) {
                    Button { move(to: period.shifted(by: -1)) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(PillButtonStyle())
                        .help("Previous \(kind.noun)")
                    Button(period.isCurrent ? "Current" : "Today") {
                        move(to: .containing(Date(), kind: kind))
                    }
                    .buttonStyle(PillButtonStyle(prominent: period.isCurrent))
                    Button { move(to: period.shifted(by: 1)) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(PillButtonStyle())
                        .disabled(period.isCurrent)
                        .help("Next \(kind.noun)")
                }
            }
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 2) {
            ForEach(ReviewKind.allCases) { k in
                Button {
                    // Keep looking at the same moment in time, at the new horizon.
                    let anchor = period.isCurrent ? Date() : period.end.addingTimeInterval(-1)
                    move(to: .containing(anchor, kind: k))
                } label: {
                    Text(k.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(kind == k ? Theme.accent.opacity(0.16) : Color.clear))
                        .foregroundColor(kind == k ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func move(to new: ReviewPeriod) {
        saveNotes()
        withAnimation(Theme.ease(0.35)) { period = new }
        loadedKey = ""
        loadNotes()
    }

    private func loadNotes() {
        guard loadedKey != period.notesKey else { return }
        notes = store.journalEntry(for: period.notesKey).text
        loadedKey = period.notesKey
    }

    private func saveNotes() {
        guard !loadedKey.isEmpty else { return }
        var e = store.journalEntry(for: loadedKey)
        guard e.text != notes else { return }
        e.text = notes
        store.saveJournal(e)
    }

    // MARK: headline

    private var headlineRow: some View {
        HStack(spacing: 13) {
            StatCard(title: kind.headline, value: Fmt.signedMoney(stats.netPnL),
                     valueColor: Theme.pnl(stats.netPnL),
                     subtitle: delta(stats.netPnL, prevStats.netPnL, money: true))
            StatCard(title: "Trades", value: "\(stats.totalTrades)",
                     subtitle: "\(stats.days.count) session\(stats.days.count == 1 ? "" : "s")")
            StatCard(title: "Win Rate", value: Fmt.percent(stats.tradeWinRate),
                     subtitle: delta(stats.tradeWinRate, prevStats.tradeWinRate, suffix: "pts"))
            StatCard(title: "Profit Factor", value: Fmt.ratio(stats.profitFactor),
                     valueColor: stats.profitFactor >= 1 ? Theme.green : Theme.red,
                     subtitle: "gross profit ÷ gross loss")
            StatCard(title: "Avg Win / Loss", value: Fmt.ratio(stats.avgWinLossRatio),
                     subtitle: "\(Fmt.money(stats.avgWin, decimals: 0)) vs \(Fmt.money(-stats.avgLoss, decimals: 0))")
        }
    }

    private func delta(_ now: Double, _ before: Double, money: Bool = false, suffix: String = "") -> String {
        guard !previous.isEmpty else { return "no previous \(kind.noun) to compare" }
        let d = now - before
        let formatted = money ? Fmt.signedMoney(d, decimals: 0) : String(format: "%@%.1f", d >= 0 ? "+" : "", d)
        return "\(formatted)\(suffix.isEmpty ? "" : " \(suffix)") vs previous \(kind.noun)"
    }

    // MARK: breakdown chart

    private struct Bucket: Identifiable {
        let date: Date
        let pnl: Double
        var id: Date { date }
    }

    private var buckets: [Bucket] {
        let cal = ReviewPeriod.calendar
        var map: [Date: Double] = [:]
        for t in trades {
            guard let start = cal.dateInterval(of: kind.chartUnit, for: t.exitTime)?.start else { continue }
            map[start, default: 0] += t.netPnL
        }
        return map.map { Bucket(date: $0.key, pnl: $0.value) }.sorted { $0.date < $1.date }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: kind.chartTitle, subtitle: "Where the \(kind.noun) was won or lost")
            Chart(buckets) { b in
                BarMark(x: .value("Period", b.date, unit: kind.chartUnit),
                        y: .value("P&L", b.pnl))
                    .cornerRadius(3)
                    .foregroundStyle(b.pnl >= 0 ? Theme.green : Theme.red)
            }
            .chartXScale(domain: period.start...period.end)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.strokeSoft)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Fmt.money(v, decimals: 0))
                                .font(.mono(8.5, .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis { xAxis }
        }
        .card()
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: xAxisValues) { _ in
            AxisGridLine().foregroundStyle(Theme.strokeSoft)
            AxisValueLabel(format: xAxisFormat, centered: true, anchor: .top)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var xAxisValues: AxisMarkValues {
        switch kind {
        case .week: return .stride(by: .day)
        case .month: return .stride(by: .day, count: 5)
        case .quarter: return .stride(by: .month)
        case .year: return .stride(by: .month)
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch kind {
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .quarter, .year: return .dateTime.month(.abbreviated)
        }
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Versus Previous \(kind.rawValue)")
            if previous.isEmpty {
                Text("No trades in the previous \(kind.noun) to compare against.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                comparisonRow("Net P&L", stats.netPnL, prevStats.netPnL, money: true)
                comparisonRow("Trades", Double(stats.totalTrades), Double(prevStats.totalTrades), integer: true)
                comparisonRow("Win rate", stats.tradeWinRate, prevStats.tradeWinRate, percent: true)
                comparisonRow("Profit factor", stats.profitFactor, prevStats.profitFactor)
                comparisonRow("Avg win", stats.avgWin, prevStats.avgWin, money: true)
                comparisonRow("Avg loss", -stats.avgLoss, -prevStats.avgLoss, money: true)
                comparisonRow("Max drawdown", -stats.maxDrawdown, -prevStats.maxDrawdown, money: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func comparisonRow(_ label: String, _ now: Double, _ before: Double,
                               money: Bool = false, percent: Bool = false, integer: Bool = false) -> some View {
        let improved = now >= before
        return HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(integer ? "\(Int(now))" : format(now, money: money, percent: percent))
                .font(.mono(11, .bold))
                .foregroundColor(Theme.textPrimary)
            Image(systemName: improved ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(improved ? Theme.green : Theme.red)
                .frame(width: 12)
            Text(integer ? "\(Int(before))" : format(before, money: money, percent: percent))
                .font(.mono(10, .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private func format(_ v: Double, money: Bool, percent: Bool) -> String {
        if money { return Fmt.signedMoney(v, decimals: 0) }
        if percent { return Fmt.percent(v, decimals: 0) }
        return v.isFinite ? String(format: "%.2f", v) : "∞"
    }

    // MARK: what worked / what it cost

    private var whatWorkedCard: some View {
        let rows = Reports.bySetup(trades).filter { $0.label != "Untagged" }.prefix(6)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What Worked", subtitle: "Confluences ranked by what they returned")
            if rows.isEmpty {
                Text("No confluences tagged in this \(kind.noun). Tag your trades to see which edge is paying.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(rows)) { b in
                    HStack {
                        TagChip(text: b.label, color: b.netPnL >= 0 ? Theme.green : Theme.red)
                        Spacer()
                        Text("\(b.trades) trade\(b.trades == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                        Text(Fmt.percent(b.winRate, decimals: 0))
                            .font(.mono(10.5, .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                        PnLText(value: b.netPnL, font: .mono(11.5, .bold))
                            .frame(width: 78, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var whatItCostCard: some View {
        let rows = Reports.byMistake(trades)
        let clean = trades.filter { $0.mistakes.isEmpty }
        let flagged = trades.filter { !$0.mistakes.isEmpty }
        let cleanAvg = clean.isEmpty ? 0 : clean.reduce(0) { $0 + $1.netPnL } / Double(clean.count)
        let flaggedAvg = flagged.isEmpty ? 0 : flagged.reduce(0) { $0 + $1.netPnL } / Double(flagged.count)

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What It Cost", subtitle: "Trades where you broke your own rules")
            if rows.isEmpty {
                Label("No mistakes tagged in this \(kind.noun).", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.green)
            } else {
                ForEach(rows.prefix(5)) { b in
                    HStack {
                        TagChip(text: b.label, color: Theme.red)
                        Spacer()
                        Text("\(b.trades)×")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                        PnLText(value: b.netPnL, font: .mono(11.5, .bold))
                            .frame(width: 78, alignment: .trailing)
                    }
                }
                Divider().overlay(Theme.strokeSoft)
                HStack {
                    Text("Average trade — clean vs flagged")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    PnLText(value: cleanAvg, font: .mono(11.5, .bold))
                    Text("vs")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                    PnLText(value: flaggedAvg, font: .mono(11.5, .bold))
                }
                if !flagged.isEmpty && !clean.isEmpty && cleanAvg > flaggedAvg {
                    Text("Clean trades averaged \(Fmt.money(cleanAvg - flaggedAvg, decimals: 0)) more each.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: process check

    private var disciplineCard: some View {
        let withStop = trades.filter { $0.stopLoss != nil }.count
        let tagged = trades.filter { !$0.setups.isEmpty }.count
        let journaled = trades.filter { !$0.notes.isEmpty || !$0.screenshots.isEmpty }.count
        let avgSize = trades.isEmpty ? 0 : trades.reduce(0) { $0 + $1.volume } / Double(trades.count)
        let oversized = trades.filter { avgSize > 0 && $0.volume > avgSize * 1.75 }.count
        let busiest = stats.days.map(\.tradeCount).max() ?? 0
        let rs = trades.compactMap(\.rMultiple)

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Process Check", subtitle: "Did the plan hold, regardless of P&L?")
            HStack(spacing: 0) {
                check("Stop set", withStop, trades.count, invert: false)
                check("Confluence tagged", tagged, trades.count, invert: false)
                check("Journaled", journaled, trades.count, invert: false)
                check("Oversized", oversized, trades.count, invert: true)
                metric("Busiest session", "\(busiest) trades")
                metric("Avg R", rs.isEmpty ? "—" : Fmt.rMultiple(rs.reduce(0, +) / Double(rs.count)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func check(_ label: String, _ count: Int, _ total: Int, invert: Bool) -> some View {
        let pct = total == 0 ? 0 : Double(count) / Double(total) * 100
        let good = invert ? pct < 15 : pct >= 80
        return VStack(spacing: 5) {
            Text(Fmt.percent(pct, decimals: 0))
                .font(.mono(16, .bold))
                .foregroundColor(good ? Theme.green : (invert ? Theme.red : Theme.silver))
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundColor(Theme.textTertiary)
            Text("\(count) of \(total)")
                .font(.system(size: 9))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.mono(16, .bold))
                .foregroundColor(Theme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: best / worst

    private var bestWorstRow: some View {
        let best = trades.max(by: { $0.netPnL < $1.netPnL })
        let worst = trades.min(by: { $0.netPnL < $1.netPnL })
        return HStack(spacing: 13) {
            if let best { TradeHighlight(title: "Best Trade", trade: best) }
            if let worst, worst.id != best?.id { TradeHighlight(title: "Worst Trade", trade: worst) }
        }
    }

    // MARK: notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader(title: "Takeaway",
                              subtitle: "One change you'll carry into the next \(kind.noun)")
                Spacer()
                Button("Save") { saveNotes() }
                    .buttonStyle(PillButtonStyle())
            }
            TextEditor(text: $notes)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Best / worst trade card
// Clicking opens the trade's day in the Daily Journal, scrolled to the trade.

private struct TradeHighlight: View {
    @EnvironmentObject var store: TradeStore
    let title: String
    let trade: Trade
    @State private var hovering = false

    var body: some View {
        Button { store.showInJournal(trade) } label: {
            HStack(spacing: 12) {
                if let name = trade.screenshots.first, let img = store.loadScreenshot(name) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 128, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(Theme.stroke, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(Theme.textTertiary)
                    HStack(spacing: 7) {
                        Text(trade.symbol)
                            .font(.mono(14, .bold))
                            .foregroundColor(Theme.textPrimary)
                        DirectionBadge(direction: trade.direction)
                        PnLText(value: trade.netPnL, font: .mono(14, .bold))
                    }
                    Text(trade.notes.isEmpty ? Fmt.weekdayDate.string(from: trade.exitTime) : trade.notes)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Open in journal")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .offset(x: hovering ? 2 : 0, y: hovering ? -2 : 0)
                }
                .foregroundColor(hovering ? Theme.accent : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius + 3, style: .continuous)
                    .strokeBorder(hovering ? Theme.strokeBright : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(Theme.ease(0.25)) { hovering = h } }
        .help("Open \(Fmt.weekdayDate.string(from: trade.exitTime)) in the Daily Journal")
    }
}
