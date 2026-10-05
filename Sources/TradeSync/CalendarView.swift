import SwiftUI

// MARK: - Month grid

struct CalendarGrid: View {
    @EnvironmentObject var store: TradeStore
    let month: Date
    var compact: Bool = false
    var onSelectDay: ((String) -> Void)? = nil

    private var cal: Calendar { Calendar.current }

    private struct DayCell {
        var pnl: Double = 0
        var count: Int = 0
        var wins: Int = 0
        var winRate: Double { count == 0 ? 0 : Double(wins) / Double(count) * 100 }
    }

    private var dayStats: [String: DayCell] {
        var map: [String: DayCell] = [:]
        for t in store.scopedTrades {
            let key = t.exitTime.dayKey
            var cell = map[key] ?? DayCell()
            cell.pnl += t.netPnL
            cell.count += 1
            if t.result == .win { cell.wins += 1 }
            map[key] = cell
        }
        return map
    }

    private var weeks: [[Date?]] {
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = monthInterval.start
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: firstDay)
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for d in 0..<daysInMonth {
            cells.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0+7]) }
    }

    var body: some View {
        let stats = dayStats
        VStack(spacing: compact ? 3 : 5) {
            HStack(spacing: compact ? 3 : 5) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { d in
                    Text(compact ? String(d.prefix(1)) : d.uppercased())
                        .font(.system(size: compact ? 8.5 : 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                if !compact {
                    Text("WEEK")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 86)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { (_, week) in
                HStack(spacing: compact ? 3 : 5) {
                    ForEach(Array(week.enumerated()), id: \.offset) { (_, day) in
                        dayCell(day, stats: stats)
                    }
                    if !compact { weekCell(week, stats: stats) }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, stats: [String: DayCell]) -> some View {
        if let day {
            let key = day.dayKey
            let cell = stats[key]
            let pnl = cell?.pnl ?? 0
            let has = (cell?.count ?? 0) > 0
            let isToday = cal.isDateInToday(day)

            let bg: Color = !has ? Theme.cardElev.opacity(0.35)
                : pnl > 0.0001 ? Theme.green.opacity(0.13)
                : pnl < -0.0001 ? Theme.red.opacity(0.12)
                : Theme.textTertiary.opacity(0.12)
            let border: Color = !has ? Theme.strokeSoft
                : pnl > 0.0001 ? Theme.green.opacity(0.38)
                : pnl < -0.0001 ? Theme.red.opacity(0.38)
                : Theme.strokeSoft

            Button {
                onSelectDay?(key)
            } label: {
                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    HStack(spacing: 0) {
                        Text("\(cal.component(.day, from: day))")
                            .font(.mono(compact ? 8.5 : 10, isToday ? .bold : .medium))
                            .foregroundColor(isToday ? Theme.accent : Theme.textTertiary)
                        Spacer()
                    }
                    if has && !compact {
                        Spacer(minLength: 0)
                        Text(Fmt.money(pnl, decimals: 0))
                            .font(.mono(11.5, .bold))
                            .foregroundColor(Theme.pnl(pnl))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text("\(cell?.count ?? 0) trade\((cell?.count ?? 0) == 1 ? "" : "s")")
                            .font(.system(size: 8))
                            .foregroundColor(Theme.textTertiary)
                        Text(Fmt.percent(cell?.winRate ?? 0, decimals: 0))
                            .font(.mono(8, .medium))
                            .foregroundColor(Theme.textTertiary)
                    } else if has && compact {
                        Spacer(minLength: 0)
                        Circle().fill(Theme.pnl(pnl)).frame(width: 4, height: 4)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(compact ? 3 : 6)
                .frame(maxWidth: .infinity, minHeight: compact ? 26 : 66, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: compact ? 4 : 6).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 6)
                    .strokeBorder(isToday ? Theme.accent.opacity(0.7) : border, lineWidth: isToday ? 1.4 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onSelectDay == nil)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: compact ? 26 : 66)
        }
    }

    @ViewBuilder
    private func weekCell(_ week: [Date?], stats: [String: DayCell]) -> some View {
        let days = week.compactMap { $0 }
        let pnl = days.reduce(0.0) { $0 + (stats[$1.dayKey]?.pnl ?? 0) }
        let activeDays = days.filter { (stats[$0.dayKey]?.count ?? 0) > 0 }.count
        VStack(spacing: 3) {
            Text(activeDays > 0 ? Fmt.money(pnl, decimals: 0) : "—")
                .font(.mono(11, .bold))
                .foregroundColor(activeDays > 0 ? Theme.pnl(pnl) : Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(activeDays == 0 ? "0 days" : "\(activeDays) day\(activeDays == 1 ? "" : "s")")
                .font(.system(size: 8))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(width: 86)
        .frame(minHeight: 66)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.cardElev.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.strokeSoft, lineWidth: 1))
    }
}

// MARK: - Calendar page

struct CalendarPageView: View {
    @EnvironmentObject var store: TradeStore
    @State private var month: Date = Date().startOfDay
    @State private var selectedDay: String? = nil

    private var monthTrades: [Trade] {
        let cal = Calendar.current
        return store.scopedTrades.filter { cal.isDate($0.exitTime, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        let stats = store.stats(for: monthTrades)
        ScrollView {
            VStack(spacing: 13) {
                HStack(spacing: 13) {
                    StatCard(title: "Monthly P&L", value: Fmt.signedMoney(stats.netPnL),
                             valueColor: Theme.pnl(stats.netPnL), subtitle: "\(stats.totalTrades) trades")
                    StatCard(title: "Trading Days", value: "\(stats.days.count)",
                             subtitle: "\(stats.winningDays) green · \(stats.losingDays) red")
                    StatCard(title: "Day Win %", value: Fmt.percent(stats.dayWinRate))
                    StatCard(title: "Best Day", value: Fmt.signedMoney(stats.days.map(\.netPnL).max() ?? 0),
                             valueColor: Theme.green)
                    StatCard(title: "Worst Day", value: Fmt.signedMoney(stats.days.map(\.netPnL).min() ?? 0),
                             valueColor: Theme.red)
                }
                CalendarGrid(month: month, onSelectDay: { selectedDay = $0 })
                    .card()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Calendar", subtitle: "Daily P&L at a glance — click any day to open it") {
                HStack(spacing: 8) {
                    Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(PillButtonStyle())
                    Text(Fmt.monthYear.string(from: month))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 128)
                    Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button("Today") { month = Date().startOfDay }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
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
}

struct DayIdentifier: Identifiable {
    let key: String
    var id: String { key }
}

// MARK: - Day peek sheet (from any calendar)

struct DayDetailSheet: View {
    @EnvironmentObject var store: TradeStore
    @Environment(\.dismiss) var dismiss
    let dayKey: String

    private var dayTrades: [Trade] { store.trades(on: dayKey) }

    var body: some View {
        let pnl = dayTrades.reduce(0.0) { $0 + $1.netPnL }
        let date = Fmt.dayKey.date(from: dayKey) ?? Date()
        let wins = dayTrades.filter { $0.result == .win }.count

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.weekdayDate.string(from: date))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text(dayTrades.isEmpty ? "No trades logged"
                         : "\(dayTrades.count) trade\(dayTrades.count == 1 ? "" : "s") · \(wins) won")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                PnLText(value: pnl, font: .mono(20, .bold))
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if dayTrades.isEmpty {
                EmptyStateView(icon: "moon.zzz", title: "Nothing traded",
                               message: "Open this day in the Daily Journal to log trades or write a plan.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(dayTrades) { t in TradeRowCompact(trade: t) }
                    }
                }
            }

            let recap = store.journalEntry(for: dayKey).text
            if !recap.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    RailLabel(text: "Session Recap")
                    Text(recap)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 11)
            }

            HStack {
                Spacer()
                Button {
                    store.openJournalDay(dayKey)
                    store.page = .journal
                    dismiss()
                } label: {
                    Label("Open in Daily Journal", systemImage: "book.pages")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

struct TradeRowCompact: View {
    let trade: Trade
    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.shortTimeHM.string(from: trade.entryTime))
                .font(.mono(10.5, .medium))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 46, alignment: .leading)
            Text(trade.symbol)
                .font(.mono(12, .bold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 66, alignment: .leading)
            DirectionBadge(direction: trade.direction)
            Text("\(Fmt.volume(trade.volume))x")
                .font(.mono(10.5, .medium))
                .foregroundColor(Theme.textSecondary)
            if !trade.screenshots.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            if let r = trade.rMultiple {
                Text(Fmt.rMultiple(r))
                    .font(.mono(10.5, .semibold))
                    .foregroundColor(Theme.pnl(r))
            }
            PnLText(value: trade.netPnL, font: .mono(12.5, .bold))
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.strokeSoft, lineWidth: 1))
    }
}
