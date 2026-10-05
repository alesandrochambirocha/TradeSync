import SwiftUI

// MARK: - Daily Journal
//
// Day folders on the left, the selected day's full log on the right: every
// trade with symbol, side, size, levels, P&L, confluences and chart
// screenshots, plus a session recap for the day as a whole.

struct JournalView: View {
    @EnvironmentObject var store: TradeStore
    @State private var showDayPicker = false
    @State private var newDayDate = Date()
    @State private var confirmDeleteDay = false

    private var dayKeys: [String] { store.journalDayKeys }

    var body: some View {
        HStack(spacing: 0) {
            dayRail
            Divider().overlay(Theme.stroke)
            Group {
                if dayKeys.isEmpty {
                    EmptyStateView(icon: "calendar.badge.plus",
                                   title: "No trading days yet",
                                   message: "Create a day folder, then log every trade you took that session — symbol, size, levels, P&L, your confluences, and the TradingView screenshot.")
                } else {
                    DayLogView(dayKey: store.selectedJournalDay)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if !dayKeys.contains(store.selectedJournalDay) {
                store.selectedJournalDay = dayKeys.first ?? Date().dayKey
            }
        }
        .sheet(isPresented: $showDayPicker) {
            dayPickerSheet
        }
    }

    // MARK: day rail

    private var dayRail: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily Journal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("\(dayKeys.count) day\(dayKeys.count == 1 ? "" : "s") logged")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button {
                    newDayDate = Date()
                    showDayPicker = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .help("Create a day folder")
            }
            .padding(.horizontal, 14)
            .padding(.top, 38)
            .padding(.bottom, 12)

            Button {
                store.openJournalDay(Date().dayKey)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(Fmt.mediumDate.string(from: Date()))
                        .font(.mono(9.5, .medium))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.accent.opacity(0.09)))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(groupedByMonth, id: \.month) { group in
                        HStack {
                            RailLabel(text: group.month)
                            Spacer()
                            Text(Fmt.signedMoney(group.pnl, decimals: 0))
                                .font(.mono(9.5, .bold))
                                .foregroundColor(Theme.pnl(group.pnl))
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                        ForEach(group.days, id: \.self) { key in
                            dayRow(key)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 236)
        .background(Theme.bgSidebar.opacity(0.6))
    }

    private var groupedByMonth: [(month: String, pnl: Double, days: [String])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var map: [String: [String]] = [:]
        for key in dayKeys {
            guard let date = Fmt.dayKey.date(from: key) else { continue }
            let m = fmt.string(from: date)
            if map[m] == nil { order.append(m) }
            map[m, default: []].append(key)
        }
        return order.map { m in
            let days = map[m] ?? []
            let pnl = days.reduce(0.0) { sum, key in
                sum + store.trades(on: key).reduce(0) { $0 + $1.netPnL }
            }
            return (m, pnl, days)
        }
    }

    private func dayRow(_ key: String) -> some View {
        let trades = store.trades(on: key)
        let pnl = trades.reduce(0.0) { $0 + $1.netPnL }
        let selected = store.selectedJournalDay == key
        let date = Fmt.dayKey.date(from: key) ?? Date()
        let hasNote = !store.journalEntry(for: key).text.isEmpty
        let shots = trades.reduce(0) { $0 + $1.screenshots.count }

        return Button {
            store.selectedJournalDay = key
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(trades.isEmpty ? Theme.textTertiary.opacity(0.4) : Theme.pnl(pnl))
                    .frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.dayMonth.string(from: date))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(selected ? Theme.textPrimary : Theme.textSecondary)
                    HStack(spacing: 5) {
                        Text("\(trades.count) trade\(trades.count == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textTertiary)
                        if hasNote {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 7))
                                .foregroundColor(Theme.accent)
                        }
                        if shots > 0 {
                            HStack(spacing: 1.5) {
                                Image(systemName: "photo")
                                    .font(.system(size: 7))
                                Text("\(shots)")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(Theme.textTertiary)
                        }
                    }
                }
                Spacer()
                if !trades.isEmpty {
                    Text(Fmt.signedMoney(pnl, decimals: 0))
                        .font(.mono(10.5, .bold))
                        .foregroundColor(Theme.pnl(pnl))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(selected ? Theme.cardElev : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(selected ? Theme.stroke : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete This Day", role: .destructive) { store.deleteJournalDay(key) }
        }
    }

    private var dayPickerSheet: some View {
        VStack(spacing: 14) {
            Text("New Trading Day")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text("Pick any date to open its folder — then log the trades you took.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            DatePicker("", selection: $newDayDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accentColor(Theme.accent)
            HStack {
                Button("Cancel") { showDayPicker = false }
                    .buttonStyle(PillButtonStyle())
                Button("Open Day") {
                    store.openJournalDay(newDayDate.dayKey)
                    showDayPicker = false
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

// MARK: - One day's log

struct DayLogView: View {
    @EnvironmentObject var store: TradeStore
    let dayKey: String

    @State private var editingTrade: Trade? = nil
    @State private var showNewTrade = false
    @State private var recap = ""
    @State private var loadedKey = ""
    @State private var flashId: UUID? = nil

    private var trades: [Trade] { store.trades(on: dayKey) }
    private var date: Date { Fmt.dayKey.date(from: dayKey) ?? Date() }
    private var pnl: Double { trades.reduce(0) { $0 + $1.netPnL } }

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryStrip
                if trades.isEmpty {
                    EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                                   title: "No trades logged for this day",
                                   message: "Hit Log Trade to record your first entry — symbol, long or short, contract size, entry, stop, target, P&L, your confluences, and the chart.")
                        .frame(height: 260)
                } else {
                    ForEach(trades) { t in
                        TradeLogCard(trade: t, highlighted: flashId == t.id) { editingTrade = t }
                            .id(t.id)
                    }
                }
                recapCard
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header.background(Theme.bg)
        }
        .onAppear {
            loadRecap()
            focus(proxy)
        }
        .onChange(of: dayKey) { loadRecap(); focus(proxy) }
        .onChange(of: store.focusTradeId) { focus(proxy) }
        .sheet(isPresented: $showNewTrade) {
            TradeEntrySheet(existing: nil, dayKey: dayKey).environmentObject(store)
        }
        .sheet(item: $editingTrade) { t in
            TradeEntrySheet(existing: t, dayKey: dayKey).environmentObject(store)
        }
      }
    }

    /// Scrolls to the trade another page asked us to show, and flashes it.
    private func focus(_ proxy: ScrollViewProxy) {
        guard let id = store.focusTradeId, trades.contains(where: { $0.id == id }) else { return }
        // Let the day's layout settle before scrolling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Theme.ease(0.6)) { proxy.scrollTo(id, anchor: .top) }
            withAnimation(Theme.ease(0.3)) { flashId = id }
            store.focusTradeId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(Theme.ease(0.8)) { if flashId == id { flashId = nil } }
            }
        }
    }

    private func loadRecap() {
        guard loadedKey != dayKey else { return }
        recap = store.journalEntry(for: dayKey).text
        loadedKey = dayKey
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.weekdayDate.string(from: date))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(trades.isEmpty ? "No trades logged"
                     : "\(trades.count) trade\(trades.count == 1 ? "" : "s") · \(trades.filter { $0.result == .win }.count) won")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                showNewTrade = true
            } label: {
                Label("Log Trade", systemImage: "plus")
            }
            .buttonStyle(PillButtonStyle(prominent: true))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var summaryStrip: some View {
        let wins = trades.filter { $0.result == .win }.count
        let winRate = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100
        let best = trades.map(\.netPnL).max() ?? 0
        let worst = trades.map(\.netPnL).min() ?? 0
        let volume = trades.reduce(0.0) { $0 + $1.volume }
        return HStack(spacing: 0) {
            summaryCell("Day P&L", Fmt.signedMoney(pnl), Theme.pnl(pnl))
            summaryDivider
            summaryCell("Win Rate", trades.isEmpty ? "—" : Fmt.percent(winRate, decimals: 0), Theme.textPrimary)
            summaryDivider
            summaryCell("Best", trades.isEmpty ? "—" : Fmt.signedMoney(best, decimals: 0), Theme.pnl(best))
            summaryDivider
            summaryCell("Worst", trades.isEmpty ? "—" : Fmt.signedMoney(worst, decimals: 0), Theme.pnl(worst))
            summaryDivider
            summaryCell("Size Traded", trades.isEmpty ? "—" : Fmt.volume(volume), Theme.textPrimary)
        }
        .padding(.vertical, 12)
        .card(padding: 0)
    }

    private func summaryCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.7)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.mono(15, .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var summaryDivider: some View {
        Rectangle().fill(Theme.strokeSoft).frame(width: 1, height: 30)
    }

    private var recapCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader(title: "Session Recap",
                              subtitle: "How did you execute? What carries into tomorrow?")
                Spacer()
                Button("Save Recap") {
                    var e = store.journalEntry(for: dayKey)
                    e.text = recap
                    store.saveJournal(e)
                }
                .buttonStyle(PillButtonStyle())
            }
            TextEditor(text: $recap)
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .card()
    }
}

// MARK: - A single logged trade

struct TradeLogCard: View {
    @EnvironmentObject var store: TradeStore
    let trade: Trade
    var highlighted: Bool = false
    var onEdit: () -> Void

    @State private var preview: String? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // top line
            HStack(spacing: 10) {
                Text(trade.symbol)
                    .font(.mono(16, .bold))
                    .foregroundColor(Theme.textPrimary)
                DirectionBadge(direction: trade.direction)
                Text("\(Fmt.volume(trade.volume)) \(Contracts.unitLabel(for: trade.assetClass).lowercased())")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(Fmt.shortTimeHM.string(from: trade.entryTime))
                    .font(.mono(10, .medium))
                    .foregroundColor(Theme.textTertiary)
                if store.selectedAccount == nil, let account = store.account(for: trade.accountId) {
                    TagChip(text: account.name, color: Theme.textSecondary)
                }
                if trade.source.isBrokerSynced {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                        .help("Synced from \(trade.source.rawValue)")
                }
                if trade.rating > 0 {
                    HStack(spacing: 1.5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7.5))
                        Text("\(trade.rating)")
                            .font(.mono(9, .bold))
                    }
                    .foregroundColor(Theme.gold)
                }
                Spacer()
                if let r = trade.rMultiple {
                    Text(Fmt.rMultiple(r))
                        .font(.mono(11, .semibold))
                        .foregroundColor(Theme.pnl(r))
                }
                PnLText(value: trade.netPnL, font: .mono(17, .bold))
                ResultBadge(result: trade.result)
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Edit this trade")
            }

            if trade.needsReview {
                Button(action: onEdit) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 11))
                        Text("Synced automatically. Add your chart and why you took it")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Add notes")
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent))
                            .foregroundColor(Theme.onAccent)
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.accent.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // levels
            HStack(spacing: 0) {
                levelCell("Entry", trade.entryPrice > 0 ? Fmt.price(trade.entryPrice) : "—", Theme.textPrimary)
                levelCell("Stop", trade.stopLoss.map(Fmt.price) ?? "—", Theme.red)
                levelCell("Target", trade.takeProfit.map(Fmt.price) ?? "—", Theme.green)
                levelCell("Exit", trade.exitPrice > 0 ? Fmt.price(trade.exitPrice) : "—", Theme.textPrimary)
                levelCell("Risk", trade.plannedRisk.map { Fmt.money($0, decimals: 0) } ?? "—", Theme.textSecondary)
                levelCell("Duration", Fmt.duration(trade.duration), Theme.textSecondary)
            }
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.bg.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.strokeSoft, lineWidth: 1))

            // confluences + mistakes
            if !trade.setups.isEmpty || !trade.mistakes.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(trade.setups, id: \.self) { TagChip(text: $0, color: Theme.accent) }
                    ForEach(trade.mistakes, id: \.self) { TagChip(text: $0, color: Theme.red) }
                }
            }

            if !trade.notes.isEmpty {
                Text(trade.notes)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !trade.screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trade.screenshots, id: \.self) { name in
                            if let img = store.loadScreenshot(name) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 186, height: 106)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                        .strokeBorder(Theme.stroke, lineWidth: 1))
                                    .onTapGesture { preview = name }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: 110)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius + 3, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent.opacity(0.85)
                              : (hovering ? Theme.strokeBright : Color.clear),
                              lineWidth: highlighted ? 1.5 : 1)
        )
        .shadow(color: highlighted ? Theme.accentBright.opacity(0.18) : .clear, radius: 18)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit Trade") { onEdit() }
            Button("Delete Trade", role: .destructive) { store.delete(trade) }
        }
        .sheet(item: Binding(
            get: { preview.map { ImageRef(name: $0) } },
            set: { preview = $0?.name }
        )) { ref in
            ScreenshotViewer(name: ref.name).environmentObject(store)
        }
    }

    private func levelCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.mono(11.5, .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
