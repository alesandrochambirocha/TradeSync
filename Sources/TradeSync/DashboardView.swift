import SwiftUI
import Charts

// MARK: - Date range filtering

enum DateRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case year = "1Y"
    case all = "All"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .quarter: return "Last 90 days"
        case .year: return "Last 12 months"
        case .all: return "All time"
        }
    }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .week: return cal.date(byAdding: .day, value: -7, to: Date())
        case .month: return cal.date(byAdding: .day, value: -30, to: Date())
        case .quarter: return cal.date(byAdding: .day, value: -90, to: Date())
        case .year: return cal.date(byAdding: .year, value: -1, to: Date())
        case .all: return nil
        }
    }
}

struct DateRangePicker: View {
    @Binding var range: DateRange
    var body: some View {
        HStack(spacing: 2) {
            ForEach(DateRange.allCases) { r in
                Button {
                    range = r
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(range == r ? Theme.accent.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(range == r ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Dashboard
// Deliberately lean: four headline numbers, the P&L calendar, and a right rail
// with the equity curve and the Edge Score. Everything else lives in the
// sidebar rail or on its own page.

struct DashboardView: View {
    @EnvironmentObject var store: TradeStore
    @State private var range: DateRange = .quarter
    @State private var month: Date = Date().startOfDay
    @State private var selectedDay: String? = nil

    private var filteredTrades: [Trade] {
        guard let start = range.startDate else { return store.scopedTrades }
        return store.scopedTrades.filter { $0.exitTime >= start }
    }

    var body: some View {
        let stats = store.stats(for: filteredTrades)
        ScrollView {
            VStack(spacing: 13) {
                if store.hasSampleData { sampleBanner }
                statRow(stats)
                HStack(alignment: .top, spacing: 13) {
                    calendarCard
                    VStack(spacing: 13) {
                        cumulativeChart(stats)
                            .frame(height: 232)
                        edgeScoreCard(stats)
                            .frame(height: 300)
                    }
                    .frame(width: 320)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Dashboard", subtitle: subtitleLine(stats)) {
                DateRangePicker(range: $range)
            }
            .background(Theme.bg)
        }
        .sheet(item: Binding(
            get: { selectedDay.map { DayIdentifier(key: $0) } },
            set: { selectedDay = $0?.key }
        )) { day in
            DayDetailSheet(dayKey: day.key).environmentObject(store)
        }
    }

    private func subtitleLine(_ stats: Stats) -> String {
        if store.scopedTrades.isEmpty { return "Log a trade or connect this account in Settings to get started" }
        return "\(range.label) · \(stats.totalTrades) trades across \(stats.days.count) trading days"
    }

    private var sampleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Theme.accent)
            Text("Showing sample data so you can explore. Remove it once your own trades are in.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Button("Remove Sample Data") { store.clearSampleData() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
    }

    // MARK: headline stats — four only

    private func statRow(_ stats: Stats) -> some View {
        HStack(spacing: 13) {
            StatCard(
                title: "Net P&L",
                value: Fmt.signedMoney(stats.netPnL),
                valueColor: Theme.pnl(stats.netPnL),
                subtitle: "\(stats.totalTrades) closed trades",
                info: "Total realized net profit and loss, including commissions and swap."
            )
            StatCard(
                title: "Profit Factor",
                value: Fmt.ratio(stats.profitFactor),
                valueColor: stats.profitFactor >= 1 ? Theme.green : Theme.red,
                subtitle: "gross profit ÷ gross loss",
                info: "Above 1.0 means the strategy is net profitable.",
                accessory: AnyView(MiniGauge(fraction: min(1, stats.profitFactor / 3),
                                             color: stats.profitFactor >= 1 ? Theme.green : Theme.red))
            )
            StatCard(
                title: "Trade Win %",
                value: Fmt.percent(stats.tradeWinRate),
                subtitle: "\(stats.winCount)W · \(stats.lossCount)L",
                info: "Percentage of winning trades out of all trades taken.",
                accessory: AnyView(WinRateDonut(winRate: stats.tradeWinRate))
            )
            StatCard(
                title: "Day Win %",
                value: Fmt.percent(stats.dayWinRate),
                subtitle: "\(stats.winningDays) green · \(stats.losingDays) red days",
                info: "Percentage of trading days that finished in profit.",
                accessory: AnyView(WinRateDonut(winRate: stats.dayWinRate))
            )
        }
    }

    // MARK: calendar

    private var calendarCard: some View {
        let cal = Calendar.current
        let monthTrades = store.scopedTrades.filter { cal.isDate($0.exitTime, equalTo: month, toGranularity: .month) }
        let monthPnL = monthTrades.reduce(0.0) { $0 + $1.netPnL }
        let days = Set(monthTrades.map { $0.exitTime.dayKey }).count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)

                Text(Fmt.monthYear.string(from: month))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(minWidth: 130, alignment: .leading)

                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)

                Button("This Month") { month = Date().startOfDay }
                    .buttonStyle(PillButtonStyle())

                Spacer()

                HStack(spacing: 7) {
                    Text("MONTH")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(Theme.textTertiary)
                    Text(Fmt.signedMoney(monthPnL, decimals: 0))
                        .font(.mono(12, .bold))
                        .foregroundColor(Theme.pnl(monthPnL))
                    Text("·")
                        .foregroundColor(Theme.textTertiary)
                    Text("\(days) days")
                        .font(.mono(11, .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.cardElev))
            }
            CalendarGrid(month: month, onSelectDay: { selectedDay = $0 })
        }
        .card()
    }

    // MARK: equity curve

    private func cumulativeChart(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader(title: "Cumulative P&L", subtitle: range.label)
                Spacer()
                PnLText(value: stats.netPnL, font: .mono(13, .bold))
            }
            if stats.days.isEmpty {
                EmptyStateView(icon: "chart.xyaxis.line", title: "No data yet",
                               message: "Your equity curve appears once trades are logged.")
            } else {
                Chart(stats.days) { day in
                    AreaMark(x: .value("Date", day.date), y: .value("Cumulative", day.cumulativePnL))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.accent.opacity(0.34), Theme.accent.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", day.date), y: .value("Cumulative", day.cumulativePnL))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                }
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
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.strokeSoft)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top)
                            .font(.system(size: 8.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .card()
    }

    // MARK: edge score

    private func edgeScoreCard(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                SectionHeader(title: "Edge Score", subtitle: range.label)
                Spacer()
                Text(ScoreBand.label(stats.edge.total))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(ScoreBand.color(stats.edge.total).opacity(0.15)))
                    .foregroundColor(ScoreBand.color(stats.edge.total))
            }
            RadarChart(axes: stats.edge.axes)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // score scale
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [Theme.red, Theme.gold, Theme.accent, Theme.green],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white)
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * min(1, max(0, stats.edge.total / 100)) - 1, y: -3)
                    }
                }
                .frame(height: 10)
                HStack {
                    Text("0").font(.mono(8, .medium)).foregroundColor(Theme.textTertiary)
                    Spacer()
                    Text("\(Int(stats.edge.total.rounded())) / 100")
                        .font(.mono(9.5, .bold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("100").font(.mono(8, .medium)).foregroundColor(Theme.textTertiary)
                }
            }
        }
        .card()
    }
}
