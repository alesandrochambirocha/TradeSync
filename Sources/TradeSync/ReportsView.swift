import SwiftUI
import Charts

// MARK: - Reports
// TradeZella-style breakdowns: performance by weekday, hour, symbol, setup,
// duration, direction, plus a risk overview.

struct ReportsView: View {
    @EnvironmentObject var store: TradeStore
    @State private var range: DateRange = .all
    @State private var tab: ReportTab = .daysTimes

    enum ReportTab: String, CaseIterable, Identifiable {
        case daysTimes = "Days & Times"
        case symbols = "Symbols"
        case setups = "Setups & Mistakes"
        case risk = "Risk & Streaks"
        var id: String { rawValue }
    }

    var filtered: [Trade] {
        guard let start = range.startDate else { return store.scopedTrades }
        return store.scopedTrades.filter { $0.exitTime >= start }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // tabs
                HStack(spacing: 4) {
                    ForEach(ReportTab.allCases) { t in
                        Button {
                            tab = t
                        } label: {
                            Text(t.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 9)
                                    .fill(tab == t ? Theme.purple : Theme.card))
                                .foregroundColor(tab == t ? .white : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                if filtered.isEmpty {
                    EmptyStateView(icon: "chart.bar.xaxis",
                                   title: "No data to report on",
                                   message: "Reports light up once you have trades in the selected date range.")
                        .frame(minHeight: 380)
                } else {
                    switch tab {
                    case .daysTimes:
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Performance by Day of Week",
                                            buckets: Reports.byWeekday(filtered), sortBySortKey: true)
                            BucketChartCard(title: "Performance by Entry Hour",
                                            buckets: Reports.byHour(filtered), sortBySortKey: true)
                        }
                        .frame(height: 300)
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Performance by Trade Duration",
                                            buckets: Reports.byDuration(filtered), sortBySortKey: true)
                            BucketTableCard(title: "Day-of-Week Details",
                                            buckets: Reports.byWeekday(filtered), sortBySortKey: true)
                        }
                        .frame(height: 300)
                    case .symbols:
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Net P&L by Symbol",
                                            buckets: Array(Reports.bySymbol(filtered).prefix(12)))
                            BucketTableCard(title: "Symbol Details", buckets: Reports.bySymbol(filtered))
                        }
                        .frame(height: 340)
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Long vs Short",
                                            buckets: Reports.byDirection(filtered))
                            assetClassCard
                        }
                        .frame(height: 280)
                    case .setups:
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Net P&L by Setup",
                                            buckets: Array(Reports.bySetup(filtered).prefix(10)))
                            BucketTableCard(title: "Setup Details", buckets: Reports.bySetup(filtered))
                        }
                        .frame(height: 320)
                        HStack(alignment: .top, spacing: 14) {
                            BucketChartCard(title: "Cost of Mistakes",
                                            buckets: Reports.byMistake(filtered))
                            BucketTableCard(title: "Mistake Details", buckets: Reports.byMistake(filtered))
                        }
                        .frame(height: 300)
                    case .risk:
                        riskSection
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Reports", subtitle: "Find your edge — and your leaks") {
                DateRangePicker(range: $range)
            }
            .background(Theme.bg)
        }
    }

    private var assetClassCard: some View {
        let buckets: [BucketStat] = {
            var map: [String: [Trade]] = [:]
            for t in filtered { map[t.assetClass.rawValue, default: []].append(t) }
            return map.map { (k, ts) in
                let pnl = ts.reduce(0.0) { $0 + $1.netPnL }
                let wins = ts.filter { $0.result == .win }.count
                return BucketStat(label: k, trades: ts.count, netPnL: pnl,
                                  winRate: ts.isEmpty ? 0 : Double(wins) / Double(ts.count) * 100)
            }.sorted { $0.netPnL > $1.netPnL }
        }()
        return BucketChartCard(title: "Net P&L by Asset Class", buckets: buckets)
    }

    private var riskSection: some View {
        let stats = store.stats(for: filtered)
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                StatCard(title: "Max Drawdown",
                         value: Fmt.money(-stats.maxDrawdown),
                         valueColor: Theme.red,
                         subtitle: stats.maxDrawdownDate.map { "hit \(Fmt.mediumDate.string(from: $0)) · \(Fmt.percent(stats.maxDrawdownPct))" } ?? "—",
                         info: "Largest peak-to-trough decline of your cumulative P&L.")
                StatCard(title: "Recovery Factor",
                         value: Fmt.ratio(stats.recoveryFactor),
                         subtitle: "net profit ÷ max drawdown")
                StatCard(title: "Largest Win", value: Fmt.signedMoney(stats.largestWin), valueColor: Theme.green)
                StatCard(title: "Largest Loss", value: Fmt.signedMoney(stats.largestLoss), valueColor: Theme.red)
                StatCard(title: "Total Fees Paid", value: Fmt.money(abs(stats.totalFees)),
                         subtitle: "commissions + swap")
            }
            HStack(spacing: 14) {
                StatCard(title: "Current Day Streak",
                         value: streakText(stats.currentDayStreak, unit: "day"),
                         valueColor: stats.currentDayStreak >= 0 ? Theme.green : Theme.red)
                StatCard(title: "Current Trade Streak",
                         value: streakText(stats.currentTradeStreak, unit: "trade"),
                         valueColor: stats.currentTradeStreak >= 0 ? Theme.green : Theme.red)
                StatCard(title: "Avg Hold — Winners", value: Fmt.duration(stats.avgHoldWinners))
                StatCard(title: "Avg Hold — Losers", value: Fmt.duration(stats.avgHoldLosers),
                         info: "Holding losers much longer than winners is a classic leak.")
                StatCard(title: "Breakeven Trades", value: "\(stats.breakevenCount)")
            }
            drawdownChart(stats)
                .frame(height: 280)
        }
    }

    private func streakText(_ streak: Int, unit: String) -> String {
        if streak == 0 { return "—" }
        let n = abs(streak)
        return "\(n) \(streak > 0 ? "winning" : "losing") \(unit)\(n == 1 ? "" : "s")"
    }

    private func drawdownChart(_ stats: Stats) -> some View {
        // drawdown series from daily cumulative
        var peak = 0.0
        let points: [(date: Date, dd: Double)] = stats.days.map { d in
            peak = max(peak, d.cumulativePnL)
            return (d.date, d.cumulativePnL - peak)
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Drawdown Curve", subtitle: "How far below your equity high-water mark you were")
            Chart(points, id: \.date) { p in
                AreaMark(x: .value("Date", p.date), y: .value("Drawdown", p.dd))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.red.opacity(0.02), Theme.red.opacity(0.5)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", p.date), y: .value("Drawdown", p.dd))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.strokeSoft)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(Fmt.money(v, decimals: 0))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Theme.strokeSoft)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()
    }
}

// MARK: - Bucket chart & table cards

struct BucketChartCard: View {
    let title: String
    let buckets: [BucketStat]
    var sortBySortKey = false

    var ordered: [BucketStat] {
        sortBySortKey ? buckets.sorted { $0.sortKey < $1.sortKey } : buckets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            if ordered.isEmpty {
                EmptyStateView(icon: "chart.bar", title: "No data",
                               message: "Nothing matches in this range.")
            } else {
                Chart(ordered) { b in
                    BarMark(
                        x: .value("Bucket", b.label),
                        y: .value("Net P&L", b.netPnL)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(b.netPnL >= 0 ? Theme.green : Theme.red)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.strokeSoft)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(Fmt.money(v, decimals: 0))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .card()
    }
}

struct BucketTableCard: View {
    let title: String
    let buckets: [BucketStat]
    var sortBySortKey = false

    var ordered: [BucketStat] {
        sortBySortKey ? buckets.sorted { $0.sortKey < $1.sortKey } : buckets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            HStack {
                Text("Bucket").frame(maxWidth: .infinity, alignment: .leading)
                Text("Trades").frame(width: 60, alignment: .trailing)
                Text("Win %").frame(width: 60, alignment: .trailing)
                Text("Net P&L").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            Divider().overlay(Theme.strokeSoft)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ordered) { b in
                        HStack {
                            Text(b.label)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(b.trades)")
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 60, alignment: .trailing)
                            Text(Fmt.percent(b.winRate, decimals: 0))
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 60, alignment: .trailing)
                            PnLText(value: b.netPnL, font: .system(size: 11.5, weight: .semibold))
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        Divider().overlay(Theme.strokeSoft)
                    }
                }
            }
        }
        .card()
    }
}
